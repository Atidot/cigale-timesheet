{-# LANGUAGE NoImplicitPrelude #-}

module Utils where

import Prelude

-- this is actually from Data.List
-- | The 'isPrefixOf' function takes two lists and returns 'True'
-- iff the first list is a prefix of the second.
isPrefixOf              :: (Eq a) => [a] -> [a] -> Bool
isPrefixOf [] _         =  True
isPrefixOf _  []        =  False
isPrefixOf (x:xs) (y:ys)=  x == y && isPrefixOf xs ys

-- http://hackage.haskell.org/packages/archive/MissingH/1.1.0.3/doc/html/src/Data-List-Utils.html#replace

{- | Similar to Data.List.break, but performs the test on the entire remaining
list instead of just one element.
-}
breakList :: ([a] -> Bool) -> [a] -> ([a], [a])
breakList func = spanList (not . func)

{- | Similar to Data.List.span, but performs the test on the entire remaining
list instead of just one element. 

@spanList p xs@ is the same as @(takeWhileList p xs, dropWhileList p xs)@ 
-}
spanList :: ([a] -> Bool) -> [a] -> ([a], [a])

spanList _ [] = ([],[])
spanList func list@(x:xs) =
    if func list
       then (x:ys,zs)
       else ([],list)
    where (ys,zs) = spanList func xs

{- | Returns true if the given list starts with the specified elements;
false otherwise.  (This is an alias for "Data.List.isPrefixOf".)

Example:

> startswith "He" "Hello" -> True

-}

startswith :: Eq a => [a] -> [a] -> Bool
startswith = isPrefixOf

{- | Given a delimiter and a list (or string), split into components.

Example:

> split "," "foo,bar,,baz," -> ["foo", "bar", "", "baz", ""]

> split "ba" ",foo,bar,,baz," -> [",foo,","r,,","z,"]
-}
split :: Eq a => [a] -> [a] -> [[a]]
split _ [] = []
split delim str =
    let (firstline, remainder) = breakList (startswith delim) str
        in 
        firstline : case remainder of
                                   [] -> []
                                   x -> if x == delim
                                        then [] : []
                                        else split delim 
                                                 (drop (length delim) x)


{- | Given a list and a replacement list, replaces each occurance of the search
list with the replacement list in the operation list.

Example:

>replace "," "." "127,0,0,1" -> "127.0.0.1"

This could logically be thought of as:

>replace old new l = join new . split old $ l
-}

replace :: Eq a => [a] -> [a] -> [a] -> [a]
replace old new l = join new . split old $ l

{- | Given a delimiter and a list of items (or strings), join the items
by using the delimiter.

Example:

> join "|" ["foo", "bar", "baz"] -> "foo|bar|baz"
-}
join :: [a] -> [[a]] -> [a]
join delim l = concat (intersperse delim l)

-- | The 'maybe' function takes a default value, a function, and a 'Maybe'
-- value.  If the 'Maybe' value is 'Nothing', the function returns the
-- default value.  Otherwise, it applies the function to the value inside
-- the 'Just' and returns the result.
maybeFay :: b -> (a -> Fay b) -> Maybe a -> Fay b
maybeFay n _ Nothing  = return n
maybeFay _ f (Just x) = f x

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