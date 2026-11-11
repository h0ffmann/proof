-- The PTC rules of the video script, checked with Z3.
--
-- The video script (contextual-bandits/script/prose-pt-BR/) is written in Português Técnico
-- Controlado (PTC 1.2.0), level `leve`, for a human reader (00-como-ler.md, lines 3 to 6). PTC has
-- nine rules. At level `leve` some parts of them are required, some are recommended, and some are
-- off (the level table of the PTC SKILL.md).
--
-- This check takes the part of each rule that a program can measure on the text: a sentence
-- length, a spelling, a number format, a phrase. For every sentence (or paragraph) of the script
-- it measures that value, gives it to Z3 as a constant, states the rule as a formula over all the
-- sentences, and asks Z3 for a model of the negation. "unsat" means that no sentence breaks the
-- rule. "sat" gives the sentences that do, from the model. agda/src/TextChecks/Ptc.agda proves
-- the decision layer for every measure.
--
--     tools/text-checks/run.sh ptc               # one line per check; exit 1 if a required check fails
--     tools/text-checks/run.sh ptc --self-test   # each required check rejects a bad text, accepts a good one
--     tools/text-checks/run.sh ptc --review      # also the sentences a person must read, for each rule
--                                                # (or part of a rule) that Z3 cannot decide
--
-- The text that PTC protects is taken out before the checks (SKILL.md, "Processo", step 3): code
-- (inline and fenced), file names, URLs, citation keys, and text in quotation marks (a quotation,
-- or a label on the screen). A sentence keeps all its words for the length check.
module Ptc
  ( Sentence (..), script, level, readScript, splitSentences, snippet
  , selfTest, check
  ) where

import Data.List (nub)
import qualified Data.Map.Strict as M
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString as B
import Py
import Smt

-- | The script's folder, from the repository root.
script :: Text
script = T.pack "contextual-bandits/script/prose-pt-BR"

level :: Text
level = T.pack "leve" -- 00-como-ler.md, line 4

maxWords, maxSentences :: Int
maxWords = 35 -- PTC-5 at level leve, and 00-como-ler.md, line 6
maxSentences = 6 -- sentences per paragraph (recommended at level leve)

------------------------------------------------------------------------------------------------
-- Reading the script: paragraphs, sentences, and the protected zone

-- | A sentence (or a paragraph), with its place in the script. text: the words as written, code
-- and quotations masked as one word each; prose: the same, with the quotations taken out too
-- (what the rules apply to); raw: the sentence as written, for the report.
data Sentence = Sentence {sFile :: Text, sLine :: Int, sText :: Text, sProse :: Text, sRaw :: Text}

type Block = [(Int, Text)]

fence, divider, headingAttr, inlineCode, url, citation, quote, emphasis, italic, label, listItem,
  tableRule, caption, sentenceEnd, inlineList, abbreviation, word, key, hasWord :: Rx
fence = re "^(```|~~~)"
divider = re "^:::"
headingAttr = re "\\{[.#][^}]*\\}"
inlineCode = re "`[^`\\n]*`"
url = re "<?https?://\\S+?>?(?=[\\s)\\]]|$)"
citation = re "\\[@[^\\]]*\\]|@[A-Za-z][\\w:-]*"
quote = re "\"[^\"\\n]*\"|“[^”\\n]*”"
emphasis = re "\\*\\*([^*\\n]+?)\\*\\*"
italic = re "(?<![*\\w])\\*([^*\\n]+?)\\*(?![*\\w])" -- a foreign word or a title
label = re "^\\*\\*[^*]+\\.\\*\\*\\s*" -- **Fala.**, **Tela.**, **Código.**
listItem = re "^\\s*(?:[-*+]|\\d+\\.)\\s+"
tableRule = re "^\\|?[\\s:|-]+\\|?$"
caption = re "^:\\s+"
-- A sentence ends at . ! ? or … (and a closing quotation mark, bracket or code mark) before a
-- space and a capital letter, a digit, a quotation mark, a bracket, a code mark or an emphasis.
-- Abbreviations that end with a point are not ends.
sentenceEnd = re $
  "(?:(?<=[.!?…])|(?<=[.!?…][`\"”)\\]])|(?<=[.!?…]\\][`]))\\s+"
    ++ "(?=[\"“(\\[*`⚠A-ZÁÉÍÓÚÂÊÔÃÕÇπ0-9])"
-- An inline list: "1952 Robbins · 2010 LinUCB · ...". Each item is a unit, as in a list.
inlineList = re "\\s+·\\s+"
abbreviation = reI "\\b(?:p|ex|Sr|Sra|Dr|Dra|etc|vs|cf|N|nº)\\.$"
word = re "[^\\s|·—–⚠*]+"
key = re "^(\\w[\\w-]*):\\s*(.*)$"
hasWord = re "\\w"

s :: String -> Text
s = T.pack

group1 :: Match -> Text
group1 m = case mGroups m of
  (Just g : _) -> g
  _ -> T.empty

group2 :: Match -> Text
group2 m = case mGroups m of
  (_ : Just g : _) -> g
  _ -> T.empty

-- | Protected zone (code, URL, citation) becomes one word: X.
mask :: Text -> Text
mask = sub citation (s " ") . sub url (s " X ") . sub inlineCode (s " X ")

-- | The prose of a YAML front matter: title, subtitle and abstract. Returns (lines, end).
frontMatter :: [Text] -> (Block, Int)
frontMatter [] = ([], 0)
frontMatter lines'@(first : _)
  | strip first /= s "---" = ([], 0)
  | otherwise = (go T.empty inside, maybe (length lines') id end)
  where
    body = zip (drop 1 lines') [2 ..]
    end = case [n | (line, n) <- body, strip line == s "---"] of
      (n : _) -> Just n
      [] -> Nothing
    inside = takeWhile (\(_, n) -> maybe True (n <) end) body
    go _ [] = []
    go k ((line, n) : rest) = case matchStart key line of
      Just m ->
        let k' = group1 m
            value = strip (group2 m)
            here | (k' == s "title" || k' == s "subtitle") && not (T.null value) =
                     [(n, stripChars "\"'" value <> s "."), (n, T.empty)]
                 | otherwise = []
        in here ++ go k' rest
      Nothing
        | k == s "abstract" -> (n, strip line) : go k rest
        | otherwise -> go k rest

-- | Blocks of prose lines, with line numbers. A list item and a table cell are blocks.
paragraphs :: Text -> [Block]
paragraphs text = loop numbered False []
  where
    lines' = splitlines text
    (headBlock, start) = frontMatter lines'
    numbered = headBlock ++ zip [start + 1 ..] (drop start lines')
    flush current = [reverse current | not (null current)]
    loop [] _ current = flush current
    loop ((n, line) : rest) inCode current
      | isJust (matchStart fence stripped) = flush current ++ loop rest (not inCode) []
      | inCode || isJust (matchStart divider stripped) = loop rest inCode current
      | T.null stripped = flush current ++ loop rest inCode []
      | s "#" `T.isPrefixOf` stripped =
          let title = strip (sub headingAttr T.empty (lstripChars "#" stripped))
          in flush current ++ [[(n, title)] | not (T.null title)] ++ loop rest inCode []
      | s "|" `T.isPrefixOf` stripped =
          let cells | isJust (matchStart tableRule stripped) = []
                    | otherwise = [[(n, strip cell)] | cell <- T.splitOn (s "|") (stripChars "|" stripped)
                                                     , not (T.null (strip cell))]
          in flush current ++ cells ++ loop rest inCode []
      | isJust (matchStart listItem line) = flush current ++ loop rest inCode [(n, sub listItem T.empty line)]
      | isJust (matchStart caption stripped) =
          flush current ++ loop rest inCode [(n, sub caption T.empty stripped)]
      | otherwise = loop rest inCode ((n, stripped) : current)
      where stripped = strip line

-- | The sentences of one block, each with the line where it starts, and the number of sentences
-- (an inline list gives one unit per item, but it is one sentence).
splitSentences :: Block -> Text -> ([Sentence], Int)
splitSentences block file = walk offset ends 0 []
  where
    text = T.concat [line <> s " " | (_, line) <- block]
    bytes = enc text
    starts = scanStarts 0 block
    scanStarts _ [] = []
    scanStarts at ((n, line) : rest) = (at, n) : scanStarts (at + B.length (enc line) + 1) rest
    offset = maybe 0 mEnd (matchStart label text)
    ends = map Just (matchesFrom sentenceEnd offset text) ++ [Nothing]
    walk _ [] count acc = (reverse acc, count)
    walk pieceStart (e : rest) count acc
      | isJust e && search abbreviation piece = walk pieceStart rest count acc
      | otherwise =
          let line = if T.null piece then 0 else maximum [n | (o, n) <- starts, o <= pieceStart]
              count' = if T.null piece then count else count + 1
              units = if T.null piece then [] else
                [ Sentence file line (sub italic (s "$1") masked) prose item
                | item <- splitRx inlineList piece
                , let masked = mask (sub emphasis (s "$1") item)
                , let prose = sub italic (s " Q ") (sub quote (s " Q ") masked) ]
              next = maybe pieceStart mEnd e
          in walk next rest count' (reverse units ++ acc)
      where
        end = maybe (B.length bytes) mStart e
        piece = strip (dec (sliceB pieceStart (max end pieceStart) bytes))

-- | (sentences, paragraphs) of the script's Markdown files, given as (name, text) in path order.
readScript :: [(Text, Text)] -> ([Sentence], [Sentence])
readScript files = (concatMap fst perBlock, concatMap snd perBlock)
  where
    perBlock =
      [ (units, [Sentence name (sLine u) (T.unwords (map sText units)) (s (show count)) T.empty | u : _ <- [units]])
      | (name, text) <- files, block <- paragraphs text
      , let (units, count) = splitSentences block name ]

words' :: Sentence -> Int
words' u = length (filter (search hasWord) (findAll word (sText u)))

------------------------------------------------------------------------------------------------
-- The rules, as patterns over the prose (the protected zone is already out)

anyOf :: Bool -> [String] -> Rx
anyOf ignoreCase ps = (if ignoreCase then reI else re) (joinAlt ps)
  where joinAlt = foldr1 (\a b -> a ++ "|" ++ b) . map (\p -> "(?:" ++ p ++ ")")

vowel :: String
vowel = "aeiouáéíóúâêôãõ"

-- PTC-8: prefixes that end in a vowel (SKILL.md, PTC-8; references/ortografia-ptbr.md)
prefixV :: String
prefixV =
  "(?:micro|auto|anti|contra|semi|mini|ultra|infra|extra|multi|intra|neo|pseudo|proto|retro|macro|mega|poli|tele|hidro|termo|eletro|foto|geo|bio|socio)"

spelling, prefixHyphenVowel, trema, spellingOk :: Rx
spelling = anyOf True
  [ "\\b(?:idéia|assembléia|heróico|jibóia|geléia|européia|européias|platéia|estréia|"
      ++ "apóia|bóia|paranóia|epopéia|colméia|alcatéia|asteróide|onomatopéia|"
      ++ "jóia|jóias|idéias|heróicos|heróica)\\b" -- open diphthong in a paroxytone
  , "\\b(?:vôo|vôos|enjôo|enjôos|lêem|crêem|vêem|dêem|relêem|prevêem|abençôo|perdôo)\\b"
  , "\\b(?:pára|pêlo|pêlos|pólo|pólos|pêra)\\b" -- abolished differential accents
  , "\\b(?:co|re)-\\w+" -- co-autor, re-escrever
  , "\\bré-\\w+"
  , "\\b(?:pre|pos|pro)-(?=\\w)" -- pré-, pós-, pró- keep the accent
  , "\\bnão-\\w+" -- não-conformidade
  , "\\bsubr\\w+" -- subrotina -> sub-rotina
  , "\\binterrela\\w*" -- interrelação -> inter-relação
  , "\\bsuper-(?![hr])\\w+" -- super-usuário -> superusuário
  , "\\binter-(?!r)\\w+" -- inter-operabilidade
  , "\\b" ++ prefixV ++ "-[rs]\\w+" -- micro-serviço -> microsserviço
  , "\\b" ++ prefixV ++ "[rs][" ++ vowel ++ "]\\w*" -- microserviço -> microsserviço
  ]
-- prefix (ends in a vowel) + hyphen + a vowel: a hyphen only when the two vowels are the same
prefixHyphenVowel = reI ("\\b(" ++ prefixV ++ ")-([" ++ vowel ++ "])\\w*")
trema = re "\\b[a-zà-ú]\\w*ü\\w*" -- trema, but not in a name (Müller)
-- Words that the last pattern would take and that are right.
spellingOk = reI $
  "^(?:autor\\w*|automático\\w*|micros?|microsoft|auto(?:s|res)?|antes|contrast\\w*|termos?"
    ++ "|bios|neos|geos|fotos|polos?|telas?|telescópio\\w*|proto|retros?|semis?|minis?|macros?"
    ++ "|megas?|ultras?|infras?|extras?|multis?|intras?|socios?|eletros?|hidros?)$"

-- PTC-7: number, date, hour, unit, range
decimalPoint, numberId, numberFormat :: Rx
decimalPoint = re "(?<![\\w.,/:-])\\d+\\.\\d{1,2}(?![\\d.,])|(?<![\\w.,/:-])\\d+\\.\\d{4,}(?![\\d.,])"
-- A number with a point that is not a decimal: a scene, a version, a model, an IP-like id.
numberId = reI $
  "(?:\\b(?:cenas?|scene|takes?|seção|versão|v|V|Sonnet|Fable|Opus|Haiku|Claude|Lean|Z3|GHC"
    ++ "|OpenVoice|XTTS|Python|pandoc)\\s*(?:\\d+(?:\\.\\d+)*\\s*(?:,|e|a)\\s*)*$)"
numberFormat = anyOf False
  [ "\\b\\d{1,3}(?:,\\d{3}){2,}\\b" -- 1,000,000 (English thousands)
  , "\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b" -- 02/08/2026
  , "\\b\\d{1,2}(?::\\d{2})?\\s?(?:AM|PM|a\\.m\\.|p\\.m\\.)(?!\\w)" -- 2:30 PM
  , "\\b\\d+(?:[.,]\\d+)?(?:ms|min|GB|MB|KB|TB|kB|kg|km|cm|mm|GHz|MHz|Hz|kW|W|°C|%)(?!\\w)"
  , "\\b\\d+(?:[.,]\\d+)?\\s(?:kgs|kms|mins|GBs|MBs)\\b" -- pluralized symbol
  , "(?<![\\w-])\\d+-\\d+(?![\\w-])(?<!\\b\\d{4}-\\d{2})" -- 10-20 as a range (not 2017-12)
  ]

-- PTC-9, the part that leaves in every level: chatbot artefact, meta-text, model limit, generic end
noiseAlways :: Rx
noiseAlways = anyOf True
  [ "\\bclaro!"
  , "\\bcom certeza!"
  , "\\bperfeito!"
  , "\\b(?:ótima|boa|excelente) pergunta\\b"
  , "\\bexcelente observação\\b"
  , "\\bespero (?:ter ajudado|que (?:isso )?(?:ajude|tenha ajudado))\\b"
  , "\\bfique à vontade para\\b"
  , "\\bqualquer dúvida, estou à disposição\\b"
  , "\\bvamos (?:lá|explorar|entender|mergulhar)\\b"
  , "\\bneste documento, vamos\\b"
  , "\\ba seguir, veremos\\b"
  , "\\bem resumo, vimos\\b"
  , "\\bcom base nas informações disponíveis\\b"
  , "\\baté onde (?:sei|eu sei)\\b"
  , "\\bo futuro é promissor\\b"
  , "\\bsó o tempo dirá\\b"
  , "\\buma coisa é certa\\b"
  , "\\bvou analisar passo a passo\\b"
  , "\\bpensando nisso de forma estruturada\\b"
  , "\\bcomo (?:um )?(?:modelo de linguagem|uma IA|IA)\\b"
  ]

-- PTC-9, the part that is recommended at level leve: filler, confidence, vague attribution,
-- copula evasion, inflation
noiseFiller :: Rx
noiseFiller = anyOf True
  [ "\\balém disso\\b"
  , "\\bademais\\b"
  , "\\boutrossim\\b"
  , "\\bnesse sentido\\b"
  , "\\bquando se trata de\\b"
  , "\\bno cenário atual\\b"
  , "\\bnos dias de hoje\\b"
  , "\\bem um mundo cada vez mais\\b"
  , "\\bem (?:suma|síntese|conclusão)\\b"
  , "\\b(?:vale|cabe) (?:destacar|ressaltar|lembrar|mencionar)\\b"
  , "\\bé importante mencionar\\b"
  , "\\b(?:notavelmente|curiosamente|surpreendentemente|indiscutivelmente)\\b"
  , "\\bsem dúvida\\b"
  , "\\bde fato\\b"
  , "\\bcertamente\\b"
  , "\\b(?:estudos|especialistas|pesquisas) (?:mostram|apontam|indicam)\\b"
  , "\\bé (?:sabido|consenso) que\\b"
  , "\\b(?:atua|se configura|se destaca) (?:como|por)\\b"
  , "\\bdispõe de\\b"
  , "\\b(?:robust[oa]s?|de ponta|de última geração|sem atrito|alavancar\\w*|alavancad[oa]s?|"
      ++ "alavancando|potencializ\\w+|"
      ++ "impulsion\\w+|divisor de águas|revolucionári[oa]s?|transformador[ae]?s?|primordial)\\b"
  , "\\bnão é só\\b.{0,60}\\bé\\b"
  ]

-- PTC-1, the parts a pattern finds: mesoclisis, 3rd-person enclitic, "o mesmo" as a pronoun
clitic, cliticOk :: Rx
clitic = reI $
  "\\b\\w+-(?:se|lo|la|los|las|me|te|nos|vos|lhe|lhes|o|a|os|as)-(?:á|ão|ás|ia|iam|ei|emos|íamos)\\b"
    ++ "|\\b\\w+[áéêíô]?-(?:o|a|os|as|lo|la|los|las|lhe|lhes)\\b(?!-)"
    ++ "|\\b(?:o|a|os|as|do|da|dos|das|no|na|nos|nas|ao|à|aos|às|pelo|pela|pelos|pelas)\\s+mesm[oa]s?"
    ++ "(?=\\s*[.,;:!?)]|\\s+(?:foi|foram|é|são|está|estão|será|serão|tem|têm|deve|devem|pode|podem)\\b)"
-- "a mesma" after "é" or "sempre" is an adjective (the question is the same), not a pronoun.
cliticOk = reI $
  "\\b(?:é|são|era|eram|foi|fica|ficam|sempre|continua|continuam)\\s+(?:sempre\\s+)?"
    ++ "(?:o|a|os|as)\\s+mesm[oa]s?\\b"

-- PTC-6 at level leve: product and process names are frozen. One spelling for each.
frozen :: [String]
frozen =
  [ "3Blue1Brown", "Manim", "Desmos", "OpenVoice", "MeloTTS", "XTTS", "Piper", "Coqui", "MyShell"
  , "Lean", "Haskell", "Z3", "Netflix", "LinUCB", "CMAB", "RSI", "Claude Code", "Anthropic"
  , "globo.com", "Scala", "Python", "GitHub", "Thompson", "A/B" ]

frozenRe :: [(Text, Rx)]
frozenRe = [(s name, reI ("(?<![\\w/])\\Q" ++ name ++ "\\E(?![\\w/])")) | name <- frozen]

apostrophePlural, brVariant :: Rx
apostrophePlural = re "\\b[A-Z]{2,}'s\\b"
brVariant = reI "\\b(?:ficheiros?|utilizador(?:es)?|ecrãs?|equipas?|registos?)\\b"

frozenHits :: Text -> [Text]
frozenHits prose =
  [ m | (name, p) <- frozenRe, m <- findAll p prose
      , m /= name, not (name == s "Lean" && m == s "lean") ]
    ++ findAll apostrophePlural prose ++ findAll brVariant prose

spellingHits :: Text -> [Text]
spellingHits prose =
  filter (isNothing . matchStart spellingOk) (findAll spelling prose)
    ++ [ mText m | m <- matches prefixHyphenVowel prose
                 , T.toLower (T.takeEnd 1 (group1 m)) /= T.toLower (group2 m) ]
    ++ findAll trema prose

numberHits :: Text -> [Text]
numberHits prose =
  findAll numberFormat prose
    ++ [ mText m | m <- matches decimalPoint prose
                 , not (search numberId (dec (B.take (mStart m) (enc prose)))) ]

-- | The offset of a match in characters: "within 20 characters" counts characters, not bytes.
charAt :: Text -> Int -> Int
charAt t b = T.length (dec (B.take b (enc t)))

cliticHits :: Text -> [Text]
cliticHits prose =
  [ mText m | m <- matches clitic prose
            , let c = charAt prose (mStart m)
            , not (any (\o -> o <= c && c <= o + 20) ok) ]
  where ok = map (charAt prose . mStart) (matches cliticOk prose)

------------------------------------------------------------------------------------------------
-- The checks Z3 decides

-- | The rule: measure(unit) <= limit, for every unit. `required` at level leve; else recommended.
data Check = Check
  { cRule :: Text, cName :: Text, cRequired :: Bool, cOverSentences :: Bool
  , cMeasure :: Sentence -> Int, cLimit :: Int, cExplain :: Sentence -> Text }

hitsCheck :: String -> String -> Bool -> (Text -> [Text]) -> Check
hitsCheck rule name required find' = Check (s rule) (s name) required True
  (length . find' . sProse) 0 (T.intercalate (s ", ") . nub . find' . sProse)

checks :: [Check]
checks =
  [ Check (s "PTC-5") (s ("every sentence has at most " ++ show maxWords ++ " words")) True True
      words' maxWords (\u -> s (show (words' u) ++ " words"))
  , hitsCheck "PTC-7" "numbers, dates, hours, units and ranges in the Brazilian format" True numberHits
  , hitsCheck "PTC-8" "spelling of the 1990 Agreement (hyphen, accent, trema)" True spellingHits
  , hitsCheck "PTC-9" "no chatbot artefact, meta-text or generic conclusion" True (findAll noiseAlways)
  , hitsCheck "PTC-1" "no mesoclisis, 3rd-person enclitic, or 'o mesmo' as a pronoun" True cliticHits
  , hitsCheck "PTC-6" "product and process names in one spelling; Brazilian variant" True frozenHits
  , hitsCheck "PTC-9" "no filler, vague attribution or inflation (recommended)" False (findAll noiseFiller)
  , Check (s "PTC") (s ("at most " ++ show maxSentences ++ " sentences in a paragraph (recommended)")) False False
      (read . T.unpack . sProse) maxSentences (\u -> sProse u <> s " sentences")
  ]

-- | Ask Z3 for a unit with measure > limit. Returns (holds, the units of the model).
prove :: Check -> [Sentence] -> IO (Bool, [Sentence])
prove c units = do
  r <- brokenInts (fromIntegral (cLimit c)) (map (fromIntegral . cMeasure c) units)
  pure $ case r of
    Nothing -> (True, [])
    Just is -> (False, map (units !!) is)

------------------------------------------------------------------------------------------------
-- What Z3 cannot decide: the sentences a person reads, for each rule

reviewRules :: [(Text, Text, Maybe Rx)]
reviewRules =
  [ ( s "PTC-1"
    , s ("every finite clause has a lexical subject; no pronoun or demonstrative points "
        ++ "outside its sentence; no actor is invented (required). Needs a parse and the reference of "
        ++ "each pronoun. Read the sentences that open with a pronoun or a demonstrative.")
    , Just (re ("^(?:\\W*)(?:Ele|Ela|Eles|Elas|Esse|Essa|Esses|Essas|Isso|Este|Esta|Isto|Aquele"
                ++ "|Aquela|Aquilo|Nesse|Nessa|Neste|Nesta|Disso|Desse|Dessa)\\b")) )
  , ( s "PTC-1"
    , s ("no proclitic 3rd-person pronoun ('o calcula', 'a mostra'): 'o' and 'a' are also "
        ++ "articles, so only a parse tells them apart. Read the sentences with 'o'/'a' before a verb "
        ++ "form in -a, -e or -am after a noun or 'que'.")
    , Just (reI "\\b(?:que|não|já|se|nunca|também)\\s+(?:o|a|os|as|lhe|lhes)\\s+\\w+(?:a|e|am|em)\\b") )
  , ( s "Level table"
    , s ("a condition or a safety note opens the sentence (required). Needs the scope "
        ++ "of 'se', 'quando', 'caso', which a pattern cannot fix. Read the sentences where one of them "
        ++ "is not the first word.")
    , Just (reI "(?<!^)(?<!\\W\\s)(?:,\\s*(?:se|quando|caso)\\s|\\s(?:exceto|a menos que|desde que)\\s)") )
  , ( s "PTC-2"
    , s ("no gerund that joins two clauses (recommended). A gerund after 'estar' is fine; "
        ++ "only the meaning tells the two apart. Read the sentences with a gerund after a comma.")
    , Just (reI ",\\s+\\w+ndo\\b") )
  , ( s "PTC-3"
    , s ("one meaning per modal; no hedge (recommended, a social hedge is fine). 'deve' is "
        ++ "obligation or probability, 'pode' is permission or capacity: only the meaning decides. "
        ++ "Read the sentences with a modal.")
    , Just (reI "\\b(?:dev[eo]\\w*|deveria\\w*|pode\\w*|poderia\\w*|talvez)\\b") )
  , ( s "PTC-5"
    , s ("an adjective goes after its noun (recommended). Needs a part-of-speech tag. Read "
        ++ "the sentences where an adjective whose meaning changes with its place comes first.")
    , Just (reI ("\\b(?:um|uma|o|a|os|as|cada|todo|toda)\\s+(?:simples|cert[oa]s?|únic[oa]s?|nov[oa]s?"
                 ++ "|velh[oa]s?|grandes?|pobres?|antig[oa]s?|bel[oa]s?|pur[oa]s?|mer[oa]s?)\\s+[a-zçãõé]+")) )
  , ( s "PTC-6"
    , s ("one concept, one term, in the whole script (required for product and process "
        ++ "names, checked above; the rest is off at level leve). A synonym for the same concept is "
        ++ "a matter of meaning: no list can hold all of them.")
    , Nothing )
  , ( s "PTC-8"
    , s ("spelling outside the curated list (required). The check covers the four hyphen "
        ++ "cases, the trema, the open diphthong and the differential accents of the PTC reference; "
        ++ "any other word needs the VOLP of the Academia Brasileira de Letras, which has no API.")
    , Nothing )
  , ( s "PTC-9"
    , s ("a sentence that says nothing (required for chatbot artefacts, checked above). "
        ++ "The PTC test is 'what is lost if it goes?', which is a question of meaning.")
    , Nothing )
  ]

snippet :: Text -> Text
snippet raw = if T.length raw <= 100 then raw else T.take 97 raw <> s "..."

review :: [Sentence] -> [Text]
review sentences =
  s "\nRules (or parts of rules) that Z3 cannot decide: read these sentences."
    : concat
      [ (s "\n" <> rule <> s ": " <> why)
          : case candidates of
              Nothing -> []
              Just p ->
                let found = filter (search p . sProse) sentences
                in [ s "  " <> sFile u <> s ":" <> s (show (sLine u)) <> s "  " <> snippet (sRaw u) | u <- found ]
                     ++ [s ("  (" ++ show (length found) ++ " sentences)")]
      | (rule, why, candidates) <- reviewRules ]

-- Each required check must reject its BAD text and accept its GOOD text (--self-test). GOOD holds
-- the right forms that look like a break: a scene number, a model version, an ISO month, a
-- hyphen that stays, a name with a trema, "a mesma" as an adjective.
selfTexts :: M.Map Text (Text, Text)
selfTexts = M.fromList
  [ (s "PTC-5", ( s ("Esta frase tem " ++ concat (replicate 33 "muitas ") ++ "palavras.")
                , s ("Esta frase tem " ++ concat (replicate 30 "poucas ") ++ "palavras.") ))
  , (s "PTC-7", ( s "O arquivo tem 1.5 GB, a fila leva 200ms, de 10-20 itens, em 02/08/2026 às 2:30 PM."
                , s "A cena 1.4 usa o Claude Sonnet 5.5, 100.000 termos, 0,67, 67 %, 14h30, em 2017-12." ))
  , (s "PTC-8", ( s "A infra-estrutura usa micro-serviços, um co-autor e a idéia é freqüente."
                , s "O anti-inflamatório, o pré-requisito, a infraestrutura, os microsserviços e Müller." ))
  , (s "PTC-9", (s "Ótima pergunta! O futuro é promissor. Espero ter ajudado!", s "O serviço reinicia em 5 s."))
  , (s "PTC-1", ( s "O pedido chegou. O mesmo foi cancelado. Far-se-á o backup. O laço aprende a enganá-la."
                , s "A pergunta é sempre a mesma: a crença nova escolhe a mesma coisa?" ))
  , (s "PTC-6", (s "O manim desenha as API's no ecrã.", s "O Manim desenha as APIs na tela."))
  ]

selfTest :: IO ([Text], Int)
selfTest = do
  failures <- fmap concat $ sequence
    [ do let (units, _) = splitSentences [(1, text)] (s "self-test")
         (holds, _) <- prove c units
         pure [ s "FAIL  self-test " <> cRule c <> s ": " <> s (if holds then "accepts" else "rejects")
                  <> s " " <> repr text
              | holds /= shouldHold ]
    | c <- checks, cRequired c
    , let (reject, accept) = selfTexts M.! cRule c
    , (text, shouldHold) <- [(reject, False), (accept, True)] ]
  let bad = length failures
  pure ( failures ++ [ if bad == 0
                         then s "OK    self-test: every required check rejects its bad text and accepts its good text"
                         else s ("\n" ++ show bad ++ " self-test failure(s)") ]
       , if bad > 0 then 1 else 0 )

check :: [(Text, Text)] -> Bool -> IO ([Text], Int)
check files wantReview = do
  let (sentences, paras) = readScript files
      header = s ("PTC, level " ++ T.unpack level ++ ": " ++ show (length sentences) ++ " sentences and "
                  ++ show (length paras) ++ " paragraphs in " ++ T.unpack script ++ "/")
  results <- mapM
    (\c -> do
        (holds, broken) <- prove c (if cOverSentences c then sentences else paras)
        let status | holds = "OK  " | cRequired c = "FAIL" | otherwise = "NOTE"
            line = s status <> s "  " <> cRule c <> s ": " <> cName c
                     <> s (if holds then " (unsat)" else " (sat)")
            details = [ s "        " <> sFile u <> s ":" <> s (show (sLine u)) <> s ": " <> cExplain c u | u <- broken ]
        pure (line : details, not holds && cRequired c))
    checks
  let failed = length (filter snd results)
      body = header : concatMap fst results ++ (if wantReview then review sentences else [])
  pure $ if failed > 0
    then (body ++ [s ("\n" ++ show failed ++ " required PTC check(s) fail")], 1)
    else (body, 0)
