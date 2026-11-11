-- The room's demonstration mesh against the size rules of Abdolali, Hesser, Roland et al. (2026,
-- Section 5.2): piabrota's room draws its ▲ grid view with coast nodes every S0 km, then one
-- hexagonal lattice per distance band out to REACH km, spaced by
--
--     spacingAt(d) = S0 + (S1 - S0) * min(1, d / REACH)^1.4      (scripts/grid.mjs at 66e38a7)
--
-- These are NOTE lines, numbers and not proofs: the rules themselves are proved in
-- agda/src/Grids/ (`just agda`). triangle-grids/README.md, "The room's mesh, measured", quotes them.
--
--     tools/room-mesh/run.sh
module Main (main) where

import Text.Printf (printf)

s0, s1, reach :: Double
s0 = 9
s1 = 70
reach = 550

spacingAt :: Double -> Double
spacingAt d = s0 + (s1 - s0) * min 1 (max 0 d / reach) ** 1.4

bands :: [(Double, Double)]
bands = [(0.5 * s0, 40), (40, 130), (130, 300), (300, reach)]

main :: IO ()
main = do
  let sizes = [spacingAt ((a + b) / 2) | (a, b) <- bands]
  putStrLn ""
  printf "NOTE  room coast spacing %.0f km: above the 5 km floor, so no coast is finer than the paper's\n" s0
  mapM_ (\((a, b), h) -> printf "NOTE  room band %.1f-%.0f km: lattice %.2f km\n" a b h) (zip bands sizes)
  mapM_
    (\(x, y) -> do
        let ratio = y / x
        printf "NOTE  room band step %.2f -> %.2f km: ratio %.2f, %s the 30%% growth rate\n"
          x y ratio (if ratio <= 1.3 then "within" else "above" :: String))
    (zip sizes (drop 1 sizes))
