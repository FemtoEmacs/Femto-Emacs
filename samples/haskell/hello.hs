-- File: hello.hs
module Main where -- main module
-- The main module must be called Main
-- The main program must return ()

import System.Environment
-- You need this to deploy getArgs 

main= do -- Line comment
  f <- getArgs -- gets the command line
  putStrLn ("Hello, "++(nm f)) where
   nm []= []
   nm [x]= x
   nm (x:xs)= x++" "++(nm xs)

-- End code
