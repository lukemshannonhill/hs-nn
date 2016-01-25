{-# LANGUAGE DataKinds, GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StandaloneDeriving, GeneralizedNewtypeDeriving #-}

module Gradients where

import Data.Vinyl
import Data.Vinyl.Functor
import Numeric.AD

import VarArgs

-- orphan instance :(
deriving instance Num a => Num (Identity a)

data GradFunc inputs output =
  GradFunc
    { function :: HList inputs -> Identity output
    , gradient :: HList inputs -> Identity output -> HList inputs
    }

-- these types are somewhat less general than would be ideal
makeUnary :: (Floating a) => (forall b. Floating b => b -> b) -> GradFunc '[a] a
makeUnary f = GradFunc (uncurry1 f) (\inputs output -> (output * uncurry1 (diff f) inputs) :& RNil)

makeBinary :: (Num a) => (forall b. Num b => b -> b -> b) -> GradFunc '[a, a] a
makeBinary f = GradFunc (uncurry2 f) g where
  g (x :& y :& RNil) output = dx :& dy :& RNil
    where [dx, dy] = map (output *) $ grad (\[a, b] -> f a b) [x, y]

makeGrad1 :: (a -> b -> a) -> HList '[a] -> Identity b -> HList '[a]
makeGrad1 g (Identity a :& RNil) (Identity b) = Identity (g a b) :& RNil

makeGrad2 :: (a -> b -> c -> (a, b)) -> HList '[a, b] -> Identity c -> HList '[a, b]
makeGrad2 g (Identity a :& Identity b :& RNil) (Identity c) = Identity a' :& Identity b' :& RNil
  where (a', b') = g a b c

