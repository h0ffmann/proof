-- The language rule of the repository (AGENTS.md, "Language", the owner, 2026-11-09): every file
-- is in English, except a file whose path carries `pt-BR`, which is in Brazilian Portuguese. As
-- a formula, for every tracked text file f:
--
--     portuguese(f)  <->  marked_pt_br(f)
--
-- `portuguese(f)` comes from a count of stop words, with fenced code blocks and inline code left
-- out (a quoted prompt or a command is not the file's prose): a file is Portuguese when its
-- Portuguese stop words are more than twice its English ones (files with fewer than 20 stop
-- words of either language are not judged: data, short code, lists). `marked_pt_br(f)` is true
-- when `pt-BR` is in the path. Z3 gets both values of every file as constants and is asked for a
-- file that breaks the rule. agda/src/TextChecks/Language.agda proves the decision layer.
--
--     tools/text-checks/run.sh language   # one line per file that breaks the rule; exit 1 if any
module Language (judged, isPortuguese, isMarked, check) where

import Data.Text (Text)
import qualified Data.Text as T
import Py
import Smt

portugueseWords, englishWords, skipped, code :: Rx
portugueseWords = reI
  "\\b(de|que|não|para|uma|com|é|os|as|do|da|em|um|são|mais|por|como|se|dos|das|ao|pela|pelo\
  \|cada|também|mesmo|isso|essa|esse)\\b"
englishWords = reI "\\b(the|of|and|is|with|that|for|to|in|this|are|from|by|as|it|on|be|or|at|an)\\b"
-- Not judged: binaries, other people's files, generated HTML, and formats with no prose of ours.
skipped = re
  "\\.(png|jpg|jpeg|gif|webp|pdf|svg|lock|json|html|bib|tex|toml|cabal|csv|tsv|parquet|cff|nix|jsonc)$\
  \|^(LICENSES|vendor)/"
code = reS "```.*?```|`[^`\\n]*`"

minimumWords :: Int
minimumWords = 20 -- stop words of both languages together, below which a file is not judged

-- | The files of `git ls-files` that are judged.
judged :: Text -> [Text]
judged = filter (not . search skipped) . split

-- | Just True, Just False, or Nothing when the file has too few stop words to judge.
isPortuguese :: Maybe Text -> Maybe Bool
isPortuguese Nothing = Nothing
isPortuguese (Just t)
  | pt + en < minimumWords = Nothing
  | otherwise = Just (pt > 2 * en)
  where
    prose = sub code (T.pack " ") t
    pt = length (findAll portugueseWords prose)
    en = length (findAll englishWords prose)

isMarked :: Text -> Bool
isMarked = T.isInfixOf (T.pack "pt-BR")

-- | The report's lines and its exit code, for the files given as (path, text if it is UTF-8).
check :: [(Text, Maybe Text)] -> IO ([Text], Int)
check files = do
  let measured = [(path, p, isMarked path) | (path, text) <- files, Just p <- [isPortuguese text]]
  broken <- brokenXor [(p, m) | (_, p, m) <- measured]
  case broken of
    Just is | not (null is) -> do
      let line (path, p, _) = T.concat
            [ T.pack "FAIL  ", path, T.pack ": "
            , T.pack (if p then "Portuguese, but its path has no pt-BR" else "marked pt-BR, but not Portuguese") ]
      pure ( map (line . (measured !!)) is
               ++ [T.pack ("\n" ++ show (length is) ++ " file(s) break the language rule")]
           , 1 )
    _ -> pure
      ( [T.pack ("OK    " ++ show (length measured)
                 ++ " files judged: every Portuguese file is marked pt-BR, and only those (unsat)")]
      , 0 )
