{-# LANGUAGE NoImplicitPrelude #-}

module Utils where

import Prelude

-- http://stackoverflow.com/questions/18521821
strComp :: String -> String -> Ordering
strComp (_:_) [] = GT
strComp [] (_:_) = LT
strComp [] [] = EQ
strComp (x:xs) (y:ys)
    | x < y = LT
    | x > y = GT
    | otherwise = strComp xs ys

-- From Control.Monad
-- The Control.Applicative stuff
-- is cooler, but it's too much
-- to stuff here.

-- | Promote a function to a monad.
--liftM   :: (Monad m) => (a1 -> r) -> m a1 -> m r
liftM f m1              = do { x1 <- m1; return (f x1) }

-- | Promote a function to a monad, scanning the monadic arguments from
-- left to right.  For example,
--
-- >    liftM2 (+) [0,1] [0,2] = [0,2,1,3]
-- >    liftM2 (+) (Just 1) Nothing = Nothing
--
--liftM2  :: (Monad m) => (a1 -> a2 -> r) -> m a1 -> m a2 -> m r
liftM2 f m1 m2          = do { x1 <- m1; x2 <- m2; return (f x1 x2) }

-- | Promote a function to a monad, scanning the monadic arguments from
-- left to right (cf. 'liftM2').
--liftM3  :: (Monad m) => (a1 -> a2 -> a3 -> r) -> m a1 -> m a2 -> m a3 -> m r
liftM3 f m1 m2 m3       = do { x1 <- m1; x2 <- m2; x3 <- m3; return (f x1 x2 x3) }

-- | Promote a function to a monad, scanning the monadic arguments from
-- left to right (cf. 'liftM2').
---liftM4  :: (Monad m) => (a1 -> a2 -> a3 -> a4 -> r) -> m a1 -> m a2 -> m a3 -> m a4 -> m r
liftM4 f m1 m2 m3 m4    = do { x1 <- m1; x2 <- m2; x3 <- m3; x4 <- m4; return (f x1 x2 x3 x4) }

-- | Promote a function to a monad, scanning the monadic arguments from
-- left to right (cf. 'liftM2').
--liftM5  :: (Monad m) => (a1 -> a2 -> a3 -> a4 -> a5 -> r) -> m a1 -> m a2 -> m a3 -> m a4 -> m a5 -> m r
liftM5 f m1 m2 m3 m4 m5 = do { x1 <- m1; x2 <- m2; x3 <- m3; x4 <- m4; x5 <- m5; return (f x1 x2 x3 x4 x5) }

liftMaybe2 :: (a -> b -> c) -> Maybe a -> Maybe b ->  Maybe c
liftMaybe2 f (Just a) (Just b) = Just $ f a b
liftMaybe2 _ _ _                    = Nothing

liftMaybe :: (a -> b) -> Maybe a -> Maybe b
liftMaybe f (Just a) = Just $ f a
liftMaybe _ _                     = Nothing


-- | The 'fromMaybe' function takes a default value and and 'Maybe'
-- value.  If the 'Maybe' is 'Nothing', it returns the default values;
-- otherwise, it returns the value contained in the 'Maybe'.
fromMaybe     :: a -> Maybe a -> a
fromMaybe d x = case x of {Nothing -> d;Just v  -> v}

-- | The 'maybe' function takes a default value, a function, and a 'Maybe'
-- value.  If the 'Maybe' value is 'Nothing', the function returns the
-- default value.  Otherwise, it applies the function to the value inside
-- the 'Just' and returns the result.
maybeFay :: b -> (a -> Fay b) -> Maybe a -> Fay b
maybeFay n _ Nothing  = return n
maybeFay _ f (Just x) = f x
