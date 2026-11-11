-- How every statement is proved: by refutation. A theorem "premises imply conclusion" holds when
-- Z3 finds no model of "premises and not conclusion": the answer `unsat`. A model, when there is
-- one, is a counterexample and is printed. A statement that expects a counterexample (Refutes)
-- holds when Z3 finds one.
module Report (Statement (..), run, format) where

import Data.List (intercalate)
import qualified Data.Map.Strict as M
import Data.SBV
import Data.SBV.Internals (CV)

data Statement
  = Proves String String (Symbolic ([SBool], SBool)) -- name, note, (premises, conclusion)
  | Refutes String String (Symbolic ([SBool], SBool)) -- name, why
  | Line String

-- | The line of a statement: OK or FAIL, the name in a column of 34, the note.
format :: String -> Bool -> String -> String
format name holds note = (if holds then "OK  " else "FAIL") ++ "  " ++ pad 34 name ++ " " ++ note
  where pad w s = s ++ replicate (w - length s) ' '

-- | A model as one line when it fits in 60 columns, else one entry a line, sorted by name.
model :: M.Map String CV -> String
model d
  | length flat <= 60 = flat
  | otherwise = "[" ++ intercalate ",\n " entries ++ "]"
  where
    entries = [k ++ " = " ++ showValue v | (k, v) <- M.toList d]
    flat = "[" ++ intercalate ", " entries ++ "]"

refute :: Symbolic ([SBool], SBool) -> IO (Maybe (M.Map String CV))
refute body = do
  r <- sat $ do
    (premises, conclusion) <- body
    mapM_ constrain premises
    pure (sNot conclusion)
  pure (if modelExists r then Just (getModelDictionary r) else Nothing)

judge :: Statement -> IO (Bool, String)
judge (Proves _ note body) = do
  r <- refute body
  pure $ case r of
    Nothing -> (True, if null note then "no counterexample (unsat)" else note)
    Just m -> (False, "sat, counterexample " ++ model m)
judge (Refutes _ why body) = do
  r <- refute body
  pure $ case r of
    Just m -> (True, "counterexample " ++ model m ++ " (" ++ why ++ ")")
    Nothing -> (False, "no counterexample, but one was expected")
judge (Line t) = pure (True, t)

-- | Runs the statements in order, prints a line each and the summary, and gives the exit code.
run :: String -> [Statement] -> IO Int
run title items = do
  results <- mapM step items
  let judged = [h | Just h <- results]
      failed = length (filter not judged)
  putStrLn ""
  putStrLn $ if failed > 0
    then title ++ ": " ++ show failed ++ " of " ++ show (length judged) ++ " failed"
    else title ++ ": all " ++ show (length judged) ++ " hold"
  pure (if failed > 0 then 1 else 0)
  where
    step (Line t) = putStrLn t >> pure Nothing
    step s = do
      (holds, note) <- judge s
      putStrLn (format (nameOf s) holds note)
      pure (Just holds)
    nameOf (Proves n _ _) = n
    nameOf (Refutes n _ _) = n
    nameOf (Line t) = t

-- | A model value without the type SBV appends (` :: Word100`).
showValue :: CV -> String
showValue v = takeWhile' (show v)
  where
    takeWhile' s = case breakOn " :: " s of (a, _) -> a
    breakOn pat s = go "" s
      where
        go acc rest@(c : cs)
          | take (length pat) rest == pat = (reverse acc, rest)
          | otherwise = go (c : acc) cs
        go acc [] = (reverse acc, [])
