{-# LANGUAGE QuasiQuotes, OverloadedStrings, DeriveGeneric #-}

module Svn where

import qualified System.Process as Process
import qualified System.IO as IO
import Data.Time.Clock
import Data.Time.Calendar
import qualified Data.Text as T
import Data.Maybe
import Data.String.Utils
import Data.Char
import Debug.Trace
import qualified Data.Aeson as JSON
import GHC.Generics

getRepoCommits :: String -> Day -> Day -> IO [Commit]
getRepoCommits url startDate endDate = do
	let dateRange = formatDateRange startDate endDate
	(inh, Just outh, errh, pid) <- Process.createProcess (Process.proc "svn" ["log", url, "-r", dateRange]) {Process.std_out = Process.CreatePipe}
	ex <- Process.waitForProcess pid
	output <- IO.hGetContents outh
--	print $ lines output
	return $ parseCommits $ lines output

data Commit = Commit
	{
		revision :: T.Text,
		date :: T.Text,
		user :: T.Text,
		linesCount :: Int,
		comment :: String
	}
	deriving (Eq, Show, Generic)

instance JSON.ToJSON Commit

parseCommits :: [String] -> [Commit]
parseCommits [] = []
parseCommits (a:[]) = [] -- in the end only the separator is left.
-- skip the first line which is "----.."
parseCommits (separator:commit_header:blank:xs) = commit : (parseCommits $ drop linesCount xs)
	where
		commit = Commit revision date user linesCount (unlines $ take linesCount xs)
		(revision:user:date:lines:[]) = map T.strip (T.splitOn "|" (T.pack commit_header))
		linesCount = read $ fst $ break (not . isDigit) (T.unpack $ T.strip lines)

formatDateRange :: Day -> Day -> String
formatDateRange startDate endDate =
	formatDate startDate ++ ":" ++ formatDate endDate

formatDate :: Day -> String
formatDate day =
	"{" ++ (show year) ++ "-" ++ (show month) ++ "-" ++ (show dayOfMonth) ++ "}"
	where
		(year, month, dayOfMonth) = toGregorian day
