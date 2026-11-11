{-# OPTIONS --without-K --guardedness #-}

-- The program of the prose checks: it reads the arguments and the files, gives them to
-- `Prose.Cli.run`, prints its lines and exits with its code. This file does input and output
-- only, so it cannot be --safe (the standard library's IO is not); every rule and every verdict
-- is in agda/src/Prose/, which is --safe and proved.
module Main where

open import Data.List using (List; []; _∷_)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Integer using (+_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)
open import Data.Unit.Polymorphic using (⊤)
open import Function using (_$_)
import Level
open import IO
open import System.Environment using (getArgs)
open import System.Exit using (exitWith; ExitSuccess; ExitFailure)

open import Prose.Cli

readAll : List String → IO (List (String × String))
readAll []       = pure []
readAll (p ∷ ps) = readFiniteFile p >>= λ t → readAll ps >>= λ ts → pure ((p , t) ∷ ts)

readMaybe : Maybe String → IO (Maybe String)
readMaybe nothing  = pure nothing
readMaybe (just p) = readFiniteFile p >>= λ t → pure (just t)

printAll : List String → IO {Level.zero} ⊤
printAll []       = pure _
printAll (l ∷ ls) = putStrLn l >> printAll ls

main : Main
main = run $
  getArgs >>= λ args →
  readAll (files (parse args)) >>= λ texts →
  readMaybe (extra (parse args)) >>= λ dict →
  let (out , code) = execute (parse args) texts dict in
  printAll out >> exitWith (exitCode code)
  where
  exitCode : ℕ → _
  exitCode zero    = ExitSuccess
  exitCode (suc n) = ExitFailure (+ suc n)
