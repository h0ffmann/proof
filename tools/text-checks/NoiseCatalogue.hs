-- The PTC-9 noise catalogue (references/ruido-ia.md of PTC 1.2.0), checked on the video script
-- with Z3.
--
-- PTC-9 says: if a passage goes and no fact, condition or instruction is lost, it is noise. The
-- catalogue lists where that noise usually shows up in technical text written or revised by a
-- model, in four tables:
--
--     Sempre sai        out at every level, `leve` too            required at leve
--     Enchimento        out at estrito and descritivo             recommended at leve
--     Evasão de cópula  out at estrito and descritivo             off at leve
--     Inflação          out at estrito and descritivo             off at leve
--
-- Ptc.hs already checks a short form of PTC-9. This check covers the catalogue itself, entry by
-- entry, so that a change to the catalogue is a change to one row of `catalogue` below. A row is
-- either decided (the "Evite" phrase is a break wherever it stands, except in the forms that the
-- catalogue's "O que fica" section keeps; for every sentence s and every such row e, the number
-- of hits is a Z3 constant h[e][s], and Z3 is asked for a model of "some h[e][s] > 0") or read
-- (its qualifier needs the meaning of the sentence, so --review lists the sentences that carry
-- the phrase). agda/src/TextChecks/NoiseCatalogue.agda proves the decision layer.
--
--     tools/text-checks/run.sh ruido-ia                 # one line per table; exit 1 if a required table fails
--     tools/text-checks/run.sh ruido-ia --self-test     # every decided row rejects its bad text, KEEP passes
--     tools/text-checks/run.sh ruido-ia --review        # also the sentences a person must read, row by row
--     tools/text-checks/run.sh ruido-ia --level estrito # the level (default: leve, 00-como-ler.md, line 4)
module NoiseCatalogue (levelArg, selfTest, check) where

import Data.List (elemIndex, nub)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Ptc (Sentence (..), level, readScript, script, snippet, splitSentences)
import Py
import Smt

source :: Text
source = T.pack "kayquer/portugues-tecnico-controlado, references/ruido-ia.md (PTC 1.2.0)"

s :: String -> Text
s = T.pack

-- | Section -> {level: "required" | "recommended" | "off"} (the line under each table heading).
sections :: [(Text, M.Map Text Text)]
sections =
  [ (s "Sempre sai", lv "required" "required" "required")
  , (s "Enchimento", lv "recommended" "required" "required")
  , (s "Evasão de cópula", lv "off" "required" "required")
  , (s "Inflação", lv "off" "required" "required")
  ]
  where lv a b c = M.fromList [(s "leve", s a), (s "descritivo", s b), (s "estrito", s c)]

-- | A row of the catalogue. avoid: the "Evite" cell, as in ruido-ia.md; decided: Z3 decides it,
-- else a person reads the candidates; bad: a sentence a decided row must reject (self-test); why:
-- for a read row, what Z3 would need to know.
data Row = Row {rSection :: Text, rAvoid :: Text, rPattern :: Rx, rDecided :: Bool, rBad :: Text, rWhy :: Text}

alt :: String -> [String] -> Rx
alt prefix as = reI (prefix ++ "(?:" ++ foldr1 (\a b -> a ++ "|" ++ b) ["(?:" ++ a ++ ")" | a <- as] ++ ")")

p, start :: [String] -> Rx
p = alt ""
start = alt "^\\W*"

decided :: String -> String -> Rx -> String -> Row
decided section avoid pat bad = Row (s section) (s avoid) pat True (s bad) T.empty

readRow :: String -> String -> Rx -> String -> Row
readRow section avoid pat why = Row (s section) (s avoid) pat False T.empty (s why)

catalogue :: [Row]
catalogue =
  -- Sempre sai
  [ decided "Sempre sai" "Claro! / Com certeza! / Perfeito!"
      (p ["\\bclaro\\s*!", "\\bcom certeza\\s*!", "\\bperfeito\\s*!"]) "Claro! O serviço reinicia em 5 s."
  , decided "Sempre sai" "Ótima pergunta / Excelente observação"
      (p ["\\b(?:ótima|excelente|boa) pergunta\\b", "\\b(?:ótima|excelente) observação\\b"])
      "Ótima pergunta, o serviço reinicia em 5 s."
  , decided "Sempre sai" "Espero ter ajudado / Espero que isso ajude"
      (p ["\\bespero (?:ter ajudado|que (?:isso )?(?:ajude|tenha ajudado))\\b"])
      "O serviço reinicia em 5 s. Espero que isso ajude."
  , decided "Sempre sai" "Fique à vontade para / Qualquer dúvida, estou à disposição"
      (p ["\\bfique à vontade para\\b", "\\bqualquer dúvida,? estou à disposição\\b", "\\bestou à disposição\\b"])
      "Fique à vontade para abrir um chamado."
  , decided "Sempre sai" "Vamos lá / Vamos explorar / Vamos entender"
      (p ["\\bvamos (?:lá|explorar|entender)\\b"]) "Vamos entender o cache."
  , readRow "Sempre sai" "Vamos + another verb (the same false collaborative opening)"
      (p ["\\bvamos (?!lá\\b|explorar\\b|entender\\b)\\w+"])
      ("the table names three verbs; with another verb, whether the opening delays the "
        ++ "subject or is the subject is meaning, and 1st person is allowed at leve")
  , decided "Sempre sai" "Neste documento, vamos abordar… / A seguir, veremos…"
      (p ["\\bneste (?:documento|texto|artigo|vídeo),? vamos\\b", "\\ba seguir,? veremos\\b"])
      "Neste documento, vamos abordar o cache."
  , decided "Sempre sai" "Em resumo, vimos que…" (p ["\\bem resumo,? vimos\\b"])
      "Em resumo, vimos que o cache expira."
  , decided "Sempre sai" "Com base nas informações disponíveis / Até onde sei"
      (p ["\\bcom base nas informações disponíveis\\b", "\\baté onde (?:eu )?sei\\b"])
      "Até onde sei, o cache expira em 60 s."
  , decided "Sempre sai" "O futuro é promissor / Só o tempo dirá / Uma coisa é certa"
      (p ["\\bo futuro é promissor\\b", "\\bsó o tempo dirá\\b", "\\buma coisa é certa\\b"]) "Só o tempo dirá."
  , decided "Sempre sai" "Vou analisar passo a passo / Pensando nisso de forma estruturada"
      (p ["\\bvou analisar passo a passo\\b", "\\bpensando nisso de forma estruturada\\b"])
      "Vou analisar passo a passo o log."
  -- Enchimento
  , decided "Enchimento" "além disso / ademais / outrossim (abrindo frase)"
      (start ["além disso\\b", "ademais\\b", "outrossim\\b"]) "Além disso, o cache expira."
  , readRow "Enchimento" "além disso / ademais / outrossim (no meio da frase)"
      (p ["\\balém disso\\b", "\\bademais\\b", "\\boutrossim\\b"])
      "inside a sentence the connector may add a real second item; only the meaning tells"
  , readRow "Enchimento" "nesse sentido / dessa forma / desse modo (sem relação causal)"
      (p ["\\bnesse sentido\\b", "\\bdess[ae] (?:forma|modo|maneira)\\b"])
      "'O que fica' keeps it when it marks a real consequence; causality is meaning"
  , decided "Enchimento" "quando se trata de X" (p ["\\bquando se trata de\\b"])
      "Quando se trata de cache, o TTL é 60 s."
  , decided "Enchimento" "no cenário atual / nos dias de hoje / em um mundo cada vez mais…"
      (p ["\\bno cenário atual\\b", "\\bnos dias de hoje\\b", "\\bem um mundo cada vez mais\\b"])
      "No cenário atual, o cache expira em 60 s."
  , decided "Enchimento" "em suma / em síntese / em conclusão" (p ["\\bem (?:suma|síntese|conclusão)\\b"])
      "Em suma, o cache expira em 60 s."
  , decided "Enchimento" "vale destacar / cabe ressaltar / é importante mencionar"
      (p [ "\\b(?:vale|cabe) (?:a pena )?(?:destacar|ressaltar|mencionar|lembrar|notar)\\b"
         , "\\bé importante (?:mencionar|destacar|ressaltar|notar|lembrar)\\b" ])
      "Vale destacar que o cache expira em 60 s."
  , decided "Enchimento" "notavelmente / curiosamente / surpreendentemente"
      (p ["\\b(?:notavelmente|curiosamente|surpreendentemente)\\b"]) "Curiosamente, o cache expira em 60 s."
  , decided "Enchimento" "sem dúvida / certamente / de fato / indiscutivelmente"
      (p ["\\bsem dúvida\\b", "\\bcertamente\\b", "\\bde fato\\b", "\\bindiscutivelmente\\b"])
      "O cache, sem dúvida, expira em 60 s."
  , decided "Enchimento" "estudos mostram / especialistas apontam / pesquisas indicam"
      (p ["\\b(?:estudos|especialistas|pesquisas|pesquisadores) (?:mostram|apontam|indicam|sugerem|dizem)\\b"])
      "Estudos mostram que o cache ajuda."
  , decided "Enchimento" "é sabido que / é consenso que" (p ["\\bé (?:sabido|consenso|notório) que\\b"])
      "É sabido que o cache ajuda."
  -- Evasão de cópula
  , decided "Evasão de cópula" "atua como / funciona como / se configura como"
      (p ["\\b(?:atua|atuam|funciona|funcionam) como\\b", "\\bse configura(?:m)? como\\b"])
      "O Redis atua como cache."
  , decided "Evasão de cópula" "conta com / dispõe de / possui"
      (p ["\\bconta(?:m)? com\\b", "\\bdispõe(?:m)? de\\b", "\\bposs(?:ui|uem|uir)\\b"])
      "O cluster conta com 3 nós."
  , readRow "Evasão de cópula" "apresenta (no sentido de ter)" (p ["\\bapresenta(?:m)?\\b"])
      "'apresentar erro' and 'apresentar ao público' are other senses; the sense is meaning"
  , readRow "Evasão de cópula" "representa (no sentido de ser)" (p ["\\brepresenta(?:m)?\\b"])
      "'a seta representa o fluxo' (a symbol stands for a thing) is not a copula"
  , decided "Evasão de cópula" "se destaca por" (p ["\\bse destaca(?:m)? (?:por|pel[oa]s?)\\b"])
      "O Redis se destaca pela latência."
  -- Inflação
  , readRow "Inflação" "robusto (elogio vago)" (p ["\\brobust[oa]s?\\b"])
      "'estimador robusto' is a term; a vague praise needs the absence of a criterion"
  , readRow "Inflação" "abrangente / completo (sem dizer o que cobre)"
      (p ["\\babrangentes?\\b", "\\bcomplet[oa]s?\\b"])
      "the row is out only when the text does not say what is covered"
  , decided "Inflação" "de ponta / de última geração / estado da arte"
      (p ["\\bde ponta\\b", "\\bde última geração\\b", "\\bestado da arte\\b"]) "É um modelo de ponta."
  , decided "Inflação" "sem atrito" (p ["\\bsem atrito\\b"]) "A migração é sem atrito."
  , readRow "Inflação" "transparente (seamless) / fluido" (p ["\\btransparentes?\\b", "\\bfluid[oa]s?\\b"])
      "'proxy transparente' is a term and 'fluido' can be the physics; only meaning tells"
  , decided "Inflação" "alavancar / potencializar / impulsionar"
      -- the verb forms only: "alavanca" is also the noun, the lever of a bandit
      (p [ "\\balavanc(?:ar\\w*|ou|aram|am|ando|ad[oa]s?|amos)\\b", "\\balavanqu\\w+"
         , "\\bpotencializ\\w+", "\\bimpulsion(?:ar\\w*|ou|aram|am|ando|ad[oa]s?|a)\\b" ])
      "O cache vai alavancar a venda."
  , readRow "Inflação" "crucial / fundamental / essencial / primordial (como ênfase)"
      (p ["\\bcruci(?:al|ais)\\b", "\\bfundamenta(?:l|is)\\b", "\\bessencia(?:l|is)\\b", "\\bprimordia(?:l|is)\\b"])
      "'teorema fundamental' is a term, and the row is out only as emphasis"
  , decided "Inflação" "divisor de águas / revolucionário" (p ["\\bdivisor de águas\\b", "\\brevolucionári[oa]s?\\b"])
      "O cache é revolucionário."
  , readRow "Inflação" "transformador" (p ["\\btransformador(?:a|es|as)?\\b"])
      "a transformer (electric, or the neural network) is a thing, not a praise"
  , readRow "Inflação" "ecossistema (metáfora)" (p ["\\becossistemas?\\b"])
      "an ecosystem in biology is literal; the metaphor is meaning"
  , readRow "Inflação" "não é só X, é Y (contraste fabricado)"
      (p ["\\bnão (?:é|são) (?:só|apenas|somente)\\b.{0,80}?\\b(?:é|são)\\b"])
      "the contrast is fabricated only if nobody said it was only X; that is the context"
  ]

-- "O que fica": forms the catalogue keeps. A hit inside one of them is not a hit.
keep, cited :: Rx
keep = reI
  "\\bestimador(?:es)? robust[oa]s?\\b|\\bteorema fundamental\\b|\\bestado fundamental\\b\
  \|\\bproxy transparente\\b|\\bcontamos com (?:vocês|você|todos)\\b"
cited = re "\\[@[^\\]]*\\]|@[A-Za-z][\\w:-]*|https?://" -- "a fonte": the row is satisfied

hits :: Row -> Sentence -> Text -> [Text]
hits row unit lvl =
  [ strip (mText m) | m <- matches (rPattern row) (sProse unit)
                    , not (any (\(a, b) -> a <= mStart m && mStart m < b) kept)
                    , not (rSection row == s "Enchimento" && s "estudos" `T.isInfixOf` rAvoid row
                           && search cited (sRaw unit)) ]
  where
    -- "Contamos com vocês" is courtesy that only level leve allows ("O que fica", last item).
    kept = [ (mStart m, mEnd m) | m <- matches keep (sProse unit)
           , lvl == s "leve" || not (s "contamos" `T.isPrefixOf` T.toLower (mText m)) ]

-- | Ask Z3 for a (row, sentence) with a hit. Returns (holds, the pairs of the model).
prove :: [Row] -> [Sentence] -> Text -> IO (Bool, [(Sentence, Row)])
prove rows units lvl = do
  let cells = [(length (hits row unit lvl), (unit, row)) | row <- rows, unit <- units]
  r <- brokenInts 0 (map (fromIntegral . fst) cells)
  pure $ case r of
    Nothing -> (True, [])
    Just is -> (False, map (snd . (cells !!)) is)

levelArg :: [String] -> Either Text Text
levelArg args = case elemIndex "--level" args of
  Nothing -> Right level
  Just i ->
    let lvl = s (if i + 1 < length args then args !! (i + 1) else "")
    in if any (M.member lvl . snd) (take 1 sections) then Right lvl
       else Left (s "unknown level " <> repr lvl <> s ": leve, descritivo or estrito")

-- Texts that look like a break and are not: "O que fica", and words near a row's phrase.
good :: Text
good = s ("O estimador robusto usa a mediana. O teorema fundamental vale. "
  ++ "O cache expira em 60 s. O conector faz a ligação, e a ideia é clara. "
  ++ "A fila é o gargalo. O relatório de 2026-03 mostra 14 falhas. "
  ++ "Claro que o cache expira, e o sistema tem 3 nós. Puxe a alavanca do braço 2.")

units1 :: Text -> [Sentence]
units1 text = fst (splitSentences [(1, text)] (s "self-test"))

selfTest :: IO ([Text], Int)
selfTest = do
  rowFailures <- fmap concat $ mapM
    (\row -> do
        (holds, _) <- prove [row] (units1 (rBad row)) (s "estrito")
        pure [s "FAIL  self-test: " <> repr (rAvoid row) <> s " accepts " <> repr (rBad row) | holds])
    (filter rDecided catalogue)
  (goodHolds, pairs) <- prove (filter rDecided catalogue) (units1 good) (s "estrito")
  let goodFailures = if goodHolds then [] else
        [s "FAIL  self-test: " <> repr (rAvoid row) <> s " rejects " <> repr (sRaw unit) | (unit, row) <- pairs]
  (courtesyHolds, _) <- prove (filter (T.isInfixOf (s "conta com") . rAvoid) catalogue)
                              (units1 (s "Contamos com vocês.")) (s "leve")
  let courtesyFailures = [s "FAIL  self-test: 'Contamos com vocês' is rejected at level leve" | not courtesyHolds]
      bad = length rowFailures + (if goodHolds then 0 else 1) + length courtesyFailures
      nDecided = length (filter rDecided catalogue)
  pure ( rowFailures ++ goodFailures ++ courtesyFailures
           ++ [ if bad == 0
                  then s ("OK    self-test: each of the " ++ show nDecided ++ " decided rows rejects its bad text, and the "
                          ++ "'O que fica' text passes")
                  else s ("\n" ++ show bad ++ " self-test failure(s)") ]
       , if bad > 0 then 1 else 0 )

review :: [Sentence] -> Text -> [Text]
review sentences lvl =
  s "\nRows that Z3 cannot decide (their qualifier is meaning): read these sentences."
    : concat
      [ (s "\n" <> rSection row <> s " (" <> status <> s " at " <> lvl <> s "): " <> rAvoid row <> s ". "
           <> rWhy row <> s ".")
          : [ s "  " <> sFile u <> s ":" <> s (show (sLine u)) <> s "  ["
                <> T.intercalate (s ", ") (nub (hits row u lvl)) <> s "]  " <> snippet (sRaw u)
            | u <- found ]
          ++ [s ("  (" ++ show (length found) ++ " sentences)")]
      | row <- catalogue, not (rDecided row)
      , let status = (M.fromList sections M.! rSection row) M.! lvl
      , let found = filter (\u -> not (null (hits row u lvl))) sentences ]

check :: [(Text, Text)] -> Text -> Bool -> IO ([Text], Int)
check files lvl wantReview = do
  let (sentences, _) = readScript files
      header = s "PTC-9 noise catalogue (" <> source <> s "), level " <> lvl <> s ": "
                 <> s (show (length sentences)) <> s " sentences in " <> script <> s "/"
  results <- mapM
    (\(section, levels) -> do
        let rows = filter (\r -> rSection r == section && rDecided r) catalogue
            status = levels M.! lvl
        (holds, broken) <- prove rows sentences lvl
        let tag | holds = s "OK  "
                | otherwise = M.fromList [(s "required", s "FAIL"), (s "recommended", s "NOTE"), (s "off", s "OFF ")] M.! status
            line = tag <> s "  " <> section <> s ": " <> s (show (length rows)) <> s " decided rows, " <> status
                     <> s " at " <> lvl <> s (if holds then " (unsat)" else " (sat)")
            details = [ s "        " <> sFile u <> s ":" <> s (show (sLine u)) <> s ": "
                          <> T.intercalate (s ", ") (nub (hits row u lvl)) <> s "  (" <> rAvoid row <> s ")"
                      | (u, row) <- broken ]
        pure (line : details, not holds && status == s "required"))
    sections
  let failed = length (filter snd results)
      undecided = length (filter (not . rDecided) catalogue)
      body = header : concatMap fst results
               ++ [s ("      " ++ show undecided ++ " rows need a reader: tools/text-checks/run.sh ruido-ia --review")]
               ++ (if wantReview then review sentences lvl else [])
  pure $ if failed > 0
    then (body ++ [s ("\n" ++ show failed ++ " required table(s) of the noise catalogue fail")], 1)
    else (body, 0)
