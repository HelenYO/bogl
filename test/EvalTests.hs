module EvalTests(evalTests) where
--
-- EvalTests.hs
--
-- Holds tests for eval and related functionality
--

import Test.HUnit
import Utils
import Runtime.Eval
import Language.Syntax
import Runtime.Monad
import Runtime.Values

evalTests :: Test
evalTests = TestList [
  testEvalEquiv,
  testEvalPlusMinusTimes,
  testBadTypesPlus,
  testEval2,
  testEvalTuple,
  testEvalLetRef]

testEvalEquiv :: Test
testEvalEquiv = TestCase (
  assertEqual "Test equiv in eval"
  (Right (Vb False))
  (evalTest (eval (Binop Equiv (I 3) (I 4)))))

testEvalPlusMinusTimes :: Test
testEvalPlusMinusTimes = TestCase (
  assertEqual "Test plus, minus, times in eval"
  (Right (Vi 6))
  (evalTest (eval (Binop Plus (Binop Minus (I 1) (I 1)) (Binop Times (I 2) (I 3))))))


-- returns true on ERR value present on the right
-- helper used in testBadTypesPlus below
_unpackBadEither :: Either Exception Val -> Bool
_unpackBadEither (Right (Err _)) = True
_unpackBadEither (Left _) = False
_unpackBadEither (Right _) = False

testBadTypesPlus :: Test
testBadTypesPlus = TestCase (
  assertBool "Test bad add for bool and int"
  --(Right (Err "Could not do numerical operation on True to 2 * 3"))
  (_unpackBadEither (evalTest (eval (Binop Plus (B True) (Binop Times (I 2) (I 3)))))))


testEval2 :: Test
testEval2 = TestCase (
  assertEqual "Test eval of 2"
  (Right (Vi 2))
  (evalTest (eval (I 2))))

testEvalTuple :: Test
testEvalTuple = TestCase (
  assertEqual "Test eval tuple"
  (Right (Vt [(Vi 2),(Vi 3),(Vi 4)]))
  (evalTest (eval (Tuple [I 2, I 3, I 4]))))

testEvalLetRef :: Test
testEvalLetRef = TestCase (
  assertEqual "Test eval let and ref"
  (Right (Vi 2))
  (evalTest (eval (Let "x" (I 2) (Ref "x")))))


-- need to use run w/ buffer....runWithBuffer
ex5 :: String
ex5 = "v1 : Int\nv1 = 2\nv2 : Int\nv2 = v1"
testVarEqUsingVarEq :: Test
testVarEqUsingVarEq = TestCase (
  assertEqual("Test var eq dependent on prior var equation")
  (Right (Vi 2))
  (evalTest (eval (Let "x" (I 2) (Ref "x")))))
  )

-- test var eq dependent on prior var equation

-- test var eq dependent on prior func equation

-- test bad ordering on var equations

-- test bad ordering on func equations
