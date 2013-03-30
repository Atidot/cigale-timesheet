{-# LANGUAGE OverloadedStrings, QuasiQuotes #-}

import Data.ByteString as BS (ByteString(..), concat)
import Data.ByteString.Char8 as Char8 (split, pack)
import Data.ByteString.Lazy (fromChunks)
import System.IO.Streams (write)
import Network.Http.Client
import Data.Maybe
import Data.Text as T (Text(..), splitOn, pack, span, take, drop)
import Data.Text.Read (decimal)
import Data.Text.Encoding as TE
import Text.Printf
import Data.Time.Calendar
import Data.Time.LocalTime
import Data.List (find)

import Text.XML (Node(..))
import Text.XML.Cursor
import Text.XML.Selector.TH
import Text.XML.Scraping
import Text.HTML.DOM (parseLBS)

import qualified Util
import Event
import EventProvider

import Debug.Trace

redmineUrl = "http://redmine/"
redmineUsername = "emmanuel.touzery@lecip-its.com"
redmineUserDisplay = "Emmanuel Touzery"
redminePassword = "itak2030"

main = do
	let day = fromGregorian 2013 3 28
	maybeCookie <- login redmineUsername redminePassword
	let cookieRows = split '\n' $ fromJust maybeCookie
	let cookieValues = fmap (head . (split ';')) cookieRows
	let activityUrl = prepareActivityUrl day
	response <- Util.http activityUrl "" concatHandler $ do
		http GET "/activity"
		setHeader "Cookie" (cookieValues !! 1)
	timezone <- getCurrentTimeZone
	print $ getIssues response day timezone

prepareActivityUrl :: Day -> ByteString
prepareActivityUrl day = BS.concat ["http://redmine/activity?from=", dayBeforeStr]
	where
		dayBefore = addDays (-1) day
		(y, m, d) = toGregorian dayBefore
		dayBeforeStr = Char8.pack $ printf "%d-%02d-%02d" y m d

-- returns the cookie
login :: ByteString -> ByteString -> IO (Maybe ByteString)
login username password = do
	postForm
		(BS.concat [redmineUrl, "login"])
		[("username", redmineUsername), ("password", redminePassword)]
		(\r i -> return $ getHeader r "Set-Cookie")

-- will return Nothing if the date you want is not covered in the
-- page.
-- TODO: that may mean we need to do paging, or simply that there
-- was no activity on that day.. For instance it was week-end..
getIssues :: ByteString -> Day -> TimeZone -> Maybe [Event]
getIssues html day timezone = fmap (getIssuesForDayNode day timezone) dayNode
	where
		doc = fromDocument $ parseLBS $ fromChunks [html]
		dayNodes = queryT [jq| div#content div#activity h3 |] doc
		dayNode = find (isDayTitle day) dayNodes

isDayTitle :: Day -> Cursor -> Bool
isDayTitle day nod = dayTitle == innerTextN (node nod)
	where
		(y, m, d) = toGregorian day
		dayTitle = T.pack $ printf "%02d/%02d/%4d" m d y

getIssuesForDayNode :: Day -> TimeZone -> Cursor -> [Event]
getIssuesForDayNode day timezone dayNode = parseBugNodes day timezone bugNodes
	where
		bugNodes = filter (isElement . node) (child dlNode)
		(Just dlNode) = find (isElement . node) (following dayNode)

parseBugNodes :: Day -> TimeZone -> [Cursor] -> [Event]
parseBugNodes day timezone (bugInfo:changeInfo:rest@_) = if authorName == redmineUserDisplay
		then Event
			{
				project = Nothing, -- TODO
				desc = bugTitle,
				extraInfo =  bugComment,
				fullContents = Nothing,
				eventDate = localTimeToUTC timezone localTime
			} : (parseBugNodes day timezone rest)
		else parseBugNodes day timezone rest
	where
		bugTitle = firstNodeInnerText $ queryT [jq|a|] bugInfo
		localTime = LocalTime day (TimeOfDay hour mins 0)
		(hour, mins) = parseTimeOfDay timeOfDayStr
		timeOfDayStr = firstNodeInnerText $ queryT [jq|span.time|] bugInfo
		bugComment = firstNodeInnerText $ queryT [jq|span.description|] changeInfo
		authorName = firstNodeInnerText $ queryT [jq|span.author a|] changeInfo
		firstNodeInnerText = innerTextN . node . head
parseBugNodes _ _ [] = []

parseTimeOfDay :: T.Text -> (Int, Int)
parseTimeOfDay timeOfDayStr = (hours, mins)
	where
		(_hoursStr:minsStr:[]) = T.splitOn ":" (T.take 5 timeOfDayStr)
		(_hours:mins:[]) = fmap (Util.safePromise . decimal) [_hoursStr, minsStr]
		hours = if T.drop 6 timeOfDayStr == "pm"
			then _hours + 12
			else _hours

isElement :: Node -> Bool
isElement (NodeElement _) = True
isElement _ = False
