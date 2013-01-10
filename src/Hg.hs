{-# LANGUAGE OverloadedStrings #-}

module Hg where

import qualified System.Process as Process
import Data.Time.Clock
import Data.Time.Calendar
import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Error
import Text.Parsec.Text
import qualified Text.Parsec as T
import qualified Data.Text as T
import qualified Data.Text.IO as IO

import qualified Event
import qualified Util

getRepoCommits :: String -> Day -> Day -> String -> FilePath -> IO [Event.Event]
getRepoCommits username startDate endDate project projectPath = do
	let dateRange = formatDateRange startDate (addDays 1 endDate)
	(inh, Just outh, errh, pid) <- Process.createProcess
		(Process.proc "hg" [
			"log", "-k", username, "-d", dateRange,
			"--template", "{date|isodate}\n{desc}\n--->>>\n"])
		{
			Process.std_out = Process.CreatePipe,
			Process.cwd = Just projectPath
		}
	ex <- Process.waitForProcess pid
	output <- IO.hGetContents outh
	let parseResult = parseCommitsParsec output
	case parseResult of
		Left pe -> do
			putStrLn $ "HG: parse error: " ++ displayErrors pe
			return []
		Right x -> return $ map (uncurry $ toEvent project) x
	where
		displayErrors pe = concat $ fmap messageString (errorMessages pe)
	
toEvent :: String -> UTCTime -> T.Text -> Event.Event
toEvent project time summary = Event.Event time Event.Svn (Just project) summary

formatDateRange :: Day -> Day -> String
formatDateRange startDate endDate =
	formatDate startDate ++ " to " ++ formatDate endDate

formatDate :: Day -> String
formatDate day =
	(show year) ++ "-" ++ (show month) ++ "-" ++ (show dayOfMonth)
	where
		(year, month, dayOfMonth) = toGregorian day

-- i am lame here.. i don't know how to make a
-- parsec function taking parameters.
-- so instead of taking a parameter "project",
-- i return an array of functions taking that
-- parameter project.
-- TODO one day ask in haskell-beginners about this one.
parseCommitsParsec :: T.Text -> Either ParseError [(UTCTime, T.Text)]
parseCommitsParsec commits = parse parseCommits "" commits

parseCommits = do
	many $ parseCommit

parseCommit = do
	date <- parseDateTime
	summary <- parseSummary
	eol


	return (date, T.pack summary)

parseDateTime = do
	year <- count 4 digit
	T.char '-'
	month <- count 2 digit
	T.char '-'
	day <- count 2 digit
	T.char ' '
	hour <- count 2 digit
	T.char ':'
	mins <- count 2 digit
	T.char ' '
	oneOf "-+"
	count 4 digit
	eol
	return $ UTCTime
		(fromGregorian (Util.parsedToInteger year) (Util.parsedToInt month) (Util.parsedToInt day))
		(secondsToDiffTime $ (Util.parsedToInteger hour)*3600 + (Util.parsedToInteger mins)*60)

parseSummary = manyTill anyChar (T.try $ string "--->>>")

-- TODO copy-pasted with Svn.hs
eol = T.many $ T.oneOf "\r\n"