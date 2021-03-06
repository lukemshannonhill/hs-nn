{-# LANGUAGE GADTs, DataKinds, PolyKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes, ScopedTypeVariables #-}
--{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses #-}

module TensorDAG where

import Data.IORef
import Data.Vinyl hiding (Dict)
--import Data.Vinyl.Functor
import Data.Singletons.Prelude hiding ((:-))
import DAGIO
import GenericTensor
import Gradients
import Data.Constraint

import Misc.VarArgs
import Misc.Constraints
import GHC.TypeLits
import Data.Proxy

tensorFloat :: forall t dims. (Tensor t, IntegralL dims) => Dict (Floating (t dims))
tensorFloat =
  case (forallC :: Forall (ImpliesC1 IntegralL (CompC Floating t))) of
    Forall (Dict :: Dict (ImpliesC1 IntegralL (CompC Floating t) dims)) ->
      case (impliesC :: IntegralL dims :- (CompC Floating t dims)) of Sub Dict -> Dict

-- a bit specific
class MapCompute inputs where
  mapCompute :: HList inputs -> HList inputs

instance MapCompute '[] where
  mapCompute RNil = RNil

instance (Tensor t, MapCompute inputs) => MapCompute (t dims ': inputs) where
  mapCompute (t :& ts) = (compute <$> t) :& mapCompute ts

barrier :: (Tensor t, MapCompute inputs) => GradFunc inputs (t dims) -> GradFunc inputs (t dims)
barrier (GradFunc f b) = GradFunc f' b' where
  f' inputs = compute <$> f inputs
  b' inputs gradOut = mapCompute $ b inputs gradOut

makeDot :: forall n t. (Tensor t, IntegralN n) => Node (t '[n]) -> Node (t '[n]) -> IO (Node (t '[]))
makeDot = case tensorFloat of (Dict :: Dict (Floating (t '[]))) -> makeNode $ barrier gradDot

--mvFun :: Tensor t => GradFunc '[t '[n, m] a, t '[m] a] (t '[n] a)
--mvFun = GradFunc (uncurry2 mv) (makeGrad2 gradMV)

-- why constraint on n and not m?
makeMV :: forall t n m. (Tensor t, IntegralN n) => Node (t '[n, m]) -> Node (t '[m]) -> IO (Node (t '[n]))
makeMV = case tensorFloat of (Dict :: Dict (Floating (t '[n]))) -> makeNode $ barrier gradMV

--makeMM = makeNode mmFun

--makeMM :: (SingI n, IntegralN n, SingI k, Usable a) => Node (Tensor '[n, m] a) -> Node (Tensor '[m, k] a) -> IO (Node (Tensor '[n, k] a))
--makeMM = makeNode (uncurry2 mm, makeGrad2 gradMM)

makeSelect :: forall t n. (IntegralN n, Tensor t) => Int -> Node (t '[n]) -> IO (Node (t '[]))
makeSelect i = case tensorFloat of (Dict :: Dict (Floating (t '[]))) -> makeNode $ barrier (gradSelect i)

makeUnary :: forall t dims. (Tensor t, IntegralL dims) => (forall b. Floating b => b -> b) -> Node (t dims) -> IO (Node (t dims))
makeUnary f = case tensorFloat of (Dict :: Dict (Floating (t dims))) -> makeNode $ barrier (unaryGrad f)

makeBinary :: forall t dims. (Tensor t, IntegralL dims) => (forall b. Floating b => b -> b -> b) -> Node (t dims) -> Node (t dims) -> IO (Node (t dims))
makeBinary f = case tensorFloat of (Dict :: Dict (Floating (t dims))) -> makeNode $ barrier (binaryGrad f)

makeSource' :: forall t dims. (Tensor t, IntegralL dims) => t dims -> IO (Node (t dims))
makeSource' t = case tensorFloat of (Dict :: Dict (Floating (t dims))) -> makeSource t

test :: forall (t :: [Nat] -> *). (Tensor t, Show (N t)) => Proxy t -> IO ()
test _ = do
  m <- makeSource' $ (fill' 1 :: t '[100, 100])
  v <- makeSource' $ (oneHot 0 :: t '[100])
  
  mv <- makeMV m v
  vmv <- makeDot v mv
  
  v2 <- makeDot v v
  
  loss <- makeBinary (/) vmv v2
  
  let train = do
        --print "Step"
        
        tape <- newIORef []
        resetNode loss
        error <- evalNodeTape tape loss
        --print (scalar <$> error)
        
        case tensorFloat of (Dict :: Dict (Floating (t '[]))) -> setLearningRate (0.001) loss
        backprop =<< readIORef tape
        ascend (Some v)

  traverse (const train) [1..100]
  
  tape <- newIORef []
  resetNode loss
  error <- evalNodeTape tape loss
  print (scalar <$> error)

  
  return ()

