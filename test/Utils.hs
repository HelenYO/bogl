module Utils where
--
-- Utils.hs
--
-- Various testing utilities
--

import Runtime.Values
import Runtime.Monad
import Parser.Parser
import Text.Parsec.Error
import System.Directory
import System.FilePath

import Language.Types
import Language.Syntax
import Text.Parsec.Pos

-- | The boilerplate for a Game which is to be filled in with ValDefs
testGame :: [ValDef SourcePos] -> Game SourcePos
testGame = Game "Test" (BoardDef (5,5) intxt) (InputDef intxt)

-- relative to top-level spiel directory
examplesPath :: String
examplesPath = "examples/"

tutorialsPath :: String
tutorialsPath = examplesPath ++ "tutorials/"

getExampleFiles :: IO [String]
getExampleFiles = do
   exampleFiles  <- listDirectory examplesPath
   tutorialFiles <- listDirectory tutorialsPath
   let fullPaths = (map ((++) examplesPath) exampleFiles) ++ (map ((++) tutorialsPath) tutorialFiles)
       bglFiles  = filter (isExtensionOf ".bgl") (fullPaths)
   return bglFiles

-- used to extract value from expression
evalTest :: Eval Val -> Either Exception Val
evalTest ev = runEval (emptyEnv (0,0)) ([], [], 1) ev

isRightErr :: Either Exception Val -> Bool
isRightErr m = case m of
                Right (Err _) -> True
                _             -> False

-- | Read a single line and return the result (intended for brevity in test cases)
parseLine' :: Parser a -> String -> Either ParseError a
parseLine' pars = parseAll pars ""

logTestStmt :: String -> IO ()
logTestStmt s = do
    putStrLn $ "\n*** " ++ s ++ " ***\n"
