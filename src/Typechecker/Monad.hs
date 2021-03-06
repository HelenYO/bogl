{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : Typechecker.Monad
Description : Typechecker monad
Copyright   : (c)
License     : BSD-3
-}

module Typechecker.Monad where

import Control.Monad.State
import Control.Monad.Identity
import Control.Monad.Except
import Control.Monad.Reader
import Text.Parsec.Pos


import Language.Types hiding (piece, size)

import qualified Data.Set as S

import Language.Syntax hiding (input)
import Runtime.Builtins

import Error.Error
import Error.TypeError

-- | Types in the environment
type TypeEnv = [(Name, Type)]

-- | Typechecker environment
data Env = Env {
  types :: TypeEnv,
  input :: Xtype,
  piece :: Xtype,
  size  :: (Int, Int)
               }

-- | Initial empty environment
initEnv :: Xtype -> Xtype -> (Int, Int) -> Env
initEnv i _p s = Env [] i _p s

-- | An example environment for interal use (e.g. testing, ghci)
exampleEnv :: Env
exampleEnv = Env (builtinT intxt intxt) intxt intxt (5, 5)

-- | Typechecker state
data Stat = Stat {
  holes :: TypeEnv,
  source :: Maybe (Expr SourcePos),
  pos :: SourcePos
            }

-- | Typechecking monad
type Typechecked a = (StateT Stat (ReaderT Env (ExceptT Error Identity))) a


-- | Run a computation inside of the typechecking monad
typecheck :: Env -> Typechecked a -> Either Error (a, Stat)
typecheck e a = runIdentity . runExceptT . (flip runReaderT e) $
                (runStateT a (Stat [] Nothing (newPos "" 0 0)))

-- | Typecheck type holes
typeHoles :: Env -> Typechecked a -> Either Error (a, TypeEnv)
typeHoles e a = case typecheck e a of
  Left terr -> Left terr
  Right (x, stat) -> Right (x, holes stat)

-- | Add some types to the environment
extendEnv :: Env -> (Name, Type) -> Env
extendEnv (Env _t i _p s) v = Env (v:_t) i _p s

-- | Get the type environment
getEnv :: Typechecked TypeEnv
getEnv = types <$> ask

-- | Get the input type
getInput :: Typechecked Xtype
getInput = input <$> ask

-- | Get the piece type
getPiece :: Typechecked (Xtype)
getPiece = piece <$> ask

-- | Get the board size
getSize :: Typechecked (Int, Int)
getSize = size <$> ask

-- | Check whether (x,y) is in the bounds of the board
inBounds :: (Int, Int) -> Typechecked Bool
inBounds (x, y) = do
                    (x', y') <- getSize
                    return $ x <= x' && y <= y' && x > 0 && y > 0

-- | Extend the environment
localEnv :: ([(Name, Type)] -> [(Name, Type)]) -> Typechecked a -> Typechecked a
localEnv f e = local (\(Env a b c d) -> Env (f a) b c d) e

-- | Get the current type holes
getHoles :: Typechecked TypeEnv
getHoles = holes <$> get

-- | Set the source line
setSrc :: (Expr SourcePos) -> Typechecked ()
setSrc e = modify (\(Stat h _ x) -> Stat h (Just e) x)

-- | Set the position
setPos :: (SourcePos) -> Typechecked ()
setPos e = modify (\stat -> stat{pos = e})

-- | Get the position
getPos :: Typechecked SourcePos
getPos = pos <$> get

-- | Get the source expression
getSrc :: Typechecked (Expr ())
getSrc = do
  e <- source <$> get
  case e of
    Nothing -> unknown "Unable to get source expression!"
    Just _e -> return $ clearAnn _e

-- | Get a type from the environment
getType :: Name -> Typechecked Type
getType n = do
  env <- getEnv
  inputT <- getInput
  pieceT <- getPiece
  case (lookup n env, lookup n (builtinT inputT pieceT)) of
    (Just e, _) -> return e
    (_, Just e) -> return e
    _ -> notbound n

-- | add a type hole
addHole :: (Name, Type) -> Typechecked ()
addHole a = modify (\(Stat h s e) -> Stat (a:h) s e)

-- | Attempt to unify two types
unify :: Xtype -> Xtype -> Typechecked Xtype
unify (Tup xs) (Tup ys)
  | length xs == length ys = Tup <$> zipWithM unify xs ys
unify (Hole _) (Hole _) = undefined
unify x (Hole n) = unify (Hole n) x
unify (Hole n) x = do
  hs <- getHoles
  case lookup n hs of
    Just (Plain _t) -> if _t <= x then return x else mismatch (Plain _t) (Plain x) -- function holes FIXME
    Nothing -> addHole (n, Plain x) >> return x
    _       -> undefined -- unhandled case when a lookup does not match one of the above
unify (X y z) (X w k)
  | y <= w = return $ X w (z `S.union` k) -- take the more defined type
  | w <= y = return $ X y (z `S.union` k)
unify a b = mismatch (Plain a) (Plain b)

-- | Check if t1 has type t2 with subsumption (i.e. by subtyping)
hasType :: Xtype -> Xtype -> Typechecked Xtype
hasType (Tup xs) (Tup ys)
  | length xs == length ys = Tup <$> zipWithM hasType xs ys
hasType ta tb = if ta <= tb then return tb else mismatch (Plain ta) (Plain tb)

-- | Returns a typechecked base type
t :: Btype -> Typechecked Xtype
t b = return (X b S.empty)

-- smart constructors for type errors

-- | Gets the source expression and its position from the 'Typechecked' monad
getInfo :: Typechecked (Expr (), SourcePos)
getInfo = ((,) <$> getSrc <*> getPos)

-- | Type mismatch error
mismatch :: Type -> Type -> Typechecked a
mismatch _t1 _t2 = getInfo >>= (\(e, x) -> throwError $ cterr (Mismatch _t1 _t2 e) x)

-- | Type mismatch error for function application
appmismatch :: Name -> Type -> Type -> Typechecked a
appmismatch n _t1 _t2 = getInfo >>= (\(e, x) -> throwError $ cterr (AppMismatch n _t1 _t2 e) x)

-- | Not bound type error
notbound :: Name -> Typechecked a
notbound n  = getPos >>= \x -> throwError $ cterr (NotBound n) x

-- | Signature mismatch type error
sigmismatch :: Name -> Type -> Type -> Typechecked a
sigmismatch n _t1 _t2= getPos >>= \x -> throwError $ cterr (SigMismatch n _t1 _t2) x

-- | Signature mismatch type error
sigbadfeq :: Name -> Type -> Equation () -> Typechecked a
sigbadfeq n _t1 f = getPos >>= \x -> throwError $ cterr (SigBadFeq n _t1 f) x

-- | Unknown type error
unknown :: String -> Typechecked a
unknown s = getPos >>= \x -> throwError $ cterr (Unknown s) x

-- | Bad Op type error
badop :: Op -> Type -> Type -> Typechecked a
badop o _t1 _t2 = getInfo >>= (\(e, x) -> throwError $ cterr (BadOp o _t1 _t2 e) x)

-- | Out of Bounds type error
outofbounds :: Pos -> Pos -> Typechecked a
outofbounds _p sz = getPos >>= \x -> throwError $ cterr (OutOfBounds _p sz) x

-- | Uninitialized board type error
uninitialized :: Name -> Typechecked a
uninitialized n = getPos >>= \x -> throwError $ cterr (Uninitialized n) x

-- | Bad function application type error
badapp :: Name -> Expr SourcePos -> Typechecked a
badapp n e = getPos >>= \x -> throwError $ cterr (BadApp n (clearAnn e)) x

-- | Cannot dereference function type error
dereff :: Name -> Type -> Typechecked a
dereff n _t = getPos >>= \x -> throwError $ cterr (Dereff n _t) x

-- | Retrieve the extensions from an Xtype
extensions :: Xtype -> Typechecked (S.Set Name)
extensions (X _ xs) = return xs
extensions _        = unknown "No extension for type!" -- no extension for this
