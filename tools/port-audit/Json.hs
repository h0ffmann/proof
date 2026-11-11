-- A small JSON reader for WW3's `model/src/cmake/switches.json`, so the tool needs no JSON library.
module Json (Value (..), parse, field, list, str) where

import Data.Char (chr, isDigit, isSpace)
import Numeric (readHex)

data Value = Obj [(String, Value)] | Arr [Value] | Str String | Num Double | Bool Bool | Null
  deriving (Show)

parse :: String -> Value
parse s = case value (skip s) of
  (v, rest) | all isSpace rest -> v
            | otherwise -> error "JSON: trailing text"

skip :: String -> String
skip = dropWhile (`elem` " \t\r\n")

value :: String -> (Value, String)
value s = case s of
  '{' : r -> object (skip r) []
  '[' : r -> array (skip r) []
  '"' : r -> let (t, r') = string r in (Str t, r')
  't' : 'r' : 'u' : 'e' : r -> (Bool True, r)
  'f' : 'a' : 'l' : 's' : 'e' : r -> (Bool False, r)
  'n' : 'u' : 'l' : 'l' : r -> (Null, r)
  _ -> let (n, r) = span (\c -> isDigit c || c `elem` "+-.eE") s in (Num (readNum n), r)
  where
    readNum n = case reads (if take 1 n == "." then '0' : n else n) of
      [(d, "")] -> d
      _ -> error ("JSON: bad number " ++ n)

string :: String -> (String, String)
string = go []
  where
    go acc ('"' : r) = (reverse acc, r)
    go acc ('\\' : c : r) = case c of
      'n' -> go ('\n' : acc) r
      't' -> go ('\t' : acc) r
      'r' -> go ('\r' : acc) r
      'b' -> go ('\b' : acc) r
      'f' -> go ('\f' : acc) r
      'u' | [(n, "")] <- readHex (take 4 r) -> go (chr n : acc) (drop 4 r)
      other -> go (other : acc) r
    go acc (c : r) = go (c : acc) r
    go _ [] = error "JSON: unterminated string"

array :: String -> [Value] -> (Value, String)
array (']' : r) acc = (Arr (reverse acc), r)
array s acc =
  let (v, r) = value (skip s)
  in case skip r of
       ',' : r' -> array (skip r') (v : acc)
       ']' : r' -> (Arr (reverse (v : acc)), r')
       _ -> error "JSON: expected , or ]"

object :: String -> [(String, Value)] -> (Value, String)
object ('}' : r) acc = (Obj (reverse acc), r)
object ('"' : s) acc =
  let (k, r) = string s
  in case skip r of
       ':' : r' ->
         let (v, r'') = value (skip r')
         in case skip r'' of
              ',' : t -> object (skip t) ((k, v) : acc)
              '}' : t -> (Obj (reverse ((k, v) : acc)), t)
              _ -> error "JSON: expected , or }"
       _ -> error "JSON: expected :"
object _ _ = error "JSON: expected a key"

-- | A field of an object, or an empty array when it is missing.
field :: String -> Value -> Value
field k (Obj kvs) = maybe (Arr []) id (lookup k kvs)
field _ _ = Arr []

list :: Value -> [Value]
list (Arr vs) = vs
list _ = []

str :: Value -> String
str (Str s) = s
str (Num d) = show d
str (Bool b) = if b then "true" else "false"
str Null = "None"
str v = show v
