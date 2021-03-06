{-|
Module      : API.Run
Description : Allows running of commands via the API
Copyright   : (c)
License     : BSD-3

Holds utility run code for both /runCmds and /runCode.
Holds the routines for parsing and interpreting a BoGL Prelude and Game file.
-}

module API.Run (_runCodeWithCommands) where

import API.JSONData
import Parser.Parser
import Language.Syntax
import Language.Types
import Text.Parsec.Pos
import Text.Parsec (errorPos)
import Text.Parsec.Error

import Typechecker.Typechecker
import Runtime.Eval
import Runtime.Values
import Runtime.Monad
import Error.TypeError
import Error.Error

-- | Runs BoGL code from raw text with the given commands
-- utilizes parsePreludeAndGameText to parse the code directly,
-- without reading it from a file first
_runCodeWithCommands :: SpielCommand -> IO SpielResponses
_runCodeWithCommands sc@(SpielCommand _prelude gameFile _ _ filename) =
  (_handleParsed sc $ parsePreludeAndGameText _prelude gameFile filename)


-- | Handles result of parsing a prelude and game
_handleParsed :: SpielCommand -> IO (Either ParseError (Game SourcePos)) -> IO SpielResponses
_handleParsed (SpielCommand _ gameFile inpt buf _) parsed = do
  pparsed <- parsed
  case pparsed of
    Right game -> do
      let checked = tc game
      if success checked
        then case checkInputTypeMatch (e checked) buf of
          InputTcOk           -> return $ [SpielTypes (rtypes checked), (serverRepl game gameFile inpt (buf, [], 1))]
          InputTcMismatch x v -> return $ SpielTypes (rtypes checked) : [SpielTypeError (cterr (InputMismatch x v) $ initialPos "")]
        else return $ SpielTypes (rtypes checked) : map (SpielTypeError . snd) (errors checked)
    Left _err -> do
      let position = errorPos _err
          l = sourceLine position
          c = sourceColumn position
          in
        return $ [SpielParseError l c gameFile (show _err)]


-- |Handles running a command in the repl from the server
serverRepl :: (Game SourcePos) -> String -> String -> Buffer -> SpielResponse
serverRepl (Game _ i@(BoardDef (szx,szy) _) b vs) fn inpt buf = do
  case parseLine inpt of
    Right x -> do
      case tcexpr (environment i b vs) x of
        Right _ -> do -- Right t
          case runWithBuffer (bindings_ (szx, szy) vs) buf x of
            -- with a runtime error
            Right (_, (Err s)) -> (SpielRuntimeError (show s))

            -- program terminated normally with a value
            Right (bs, val) -> (SpielValue bs val)

            -- boards and tape returned, returns the boards for displaying on the frontend
            Left (bs, _) -> (SpielPrompt bs)

            -- runtime error encountered
            -- TODO REMOVED Redundant clause?
            --Left err -> (SpielRuntimeError (show err))

        -- typechecker encountered an error in the expression
        Left _err -> (SpielTypeError _err)
    -- bad parse
    Left _err ->
      let position = errorPos _err
          l = sourceLine position
          c = sourceColumn position in
      (SpielParseError l c fn (show _err))
