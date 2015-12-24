{-# LANGUAGE ScopedTypeVariables, DeriveGeneric, LambdaCase #-}
{-# LANGUAGE RecordWildCards, RecursiveDo, JavaScriptFFI, ForeignFunctionInterface #-}

import GHCJS.Types
import GHCJS.Foreign
import GHCJS.DOM.Element
import GHCJS.DOM.Types hiding (Text)

import Reflex
import Reflex.Dom

import GHC.Generics
import Data.Time.Clock
import qualified Data.Text as T
import Data.Text (Text)
import Data.Aeson
import Control.Monad
import Data.Time.Calendar
import Data.Time.Format
import Data.Monoid
import Control.Monad.IO.Class

-- foreign import javascript unsafe "new Pikaday({onSelect: $1})" initPikaday :: (JSFun JSString -> IO ()) -> IO Node
foreign import javascript unsafe "$1.appendChild(new Pikaday({onSelect: function(txt) {console.error(txt);}}).el)" initPikaday :: JSRef Element -> IO ()

-- url is http://localhost:8000/static/index.html
-- start cigale with .stack-work/install/x86_64-linux/lts-3.16/7.10.2/bin/cigale-timesheet

-- TODO unhardcode
initialDay :: String
initialDay = "2015-11-10"

text_ :: MonadWidget t m => Text -> m ()
text_ = text . T.unpack

-- TODO share code with the server
-- instead of copy-pasting
data TsEvent = TsEvent
    {
        pluginName :: String,
        eventIcon :: String,
        eventDate :: UTCTime,
        desc :: T.Text,
        extraInfo :: T.Text,
        fullContents :: Maybe T.Text
    } deriving (Eq, Show, Generic)
instance FromJSON TsEvent

data FetchResponse = FetchResponse
    {
        fetchedEvents :: [TsEvent],
        fetchErrors :: [String]
    } deriving (Show, Generic)
instance FromJSON FetchResponse

main :: IO ()
main = mainWidget cigaleView

modifyDay :: Integer -> String -> String
modifyDay daysCount str = case parseTimeM False defaultTimeLocale "%Y-%m-%d" str of
    Nothing  -> str
    Just day -> showGregorian (addDays daysCount day)

cigaleView :: MonadWidget t m => m ()
cigaleView = do
    stylesheet "pikaday.css"
    el "div" $ do
        previousDayBtn <- button "<<"
        rec
            curDate <- foldDyn ($) initialDay $ mergeWith (.)
                [
                    fmap (const $ modifyDay (-1)) previousDayBtn,
                    fmap (const $ modifyDay 1) nextDayBtn --,
                    -- fmap const $ tagDyn (_textInput_value dateInput) (textInputGetEnter dateInput)
                ]

            dateInput <- textInput $ def
                & textInputConfig_initialValue .~ initialDay
                & setValue .~ updated curDate
            nextDayBtn <- button ">>"
            datePicker
        let req url = xhrRequest "GET" ("/timesheet/" ++ url) def
        loadRecordsEvent <- mergeWith const <$> sequence [pure $ updated curDate, fmap (const initialDay) <$> getPostBuild]
        asyncReq <- performRequestAsync (req <$> loadRecordsEvent)
        resp <- holdDyn Nothing $ fmap decodeXhrResponse asyncReq
        void (mapDyn eventsTable resp >>= dyn)

-- https://m.reddit.com/r/reflexfrp/comments/3h3s72/rendering_dynamic_html_table/
eventsTable :: MonadWidget t m => Maybe FetchResponse -> m ()
eventsTable Nothing = text "Error reading the server's message!"
eventsTable (Just (FetchResponse events errors)) = el "table" $ mapM_ showRecord events

showRecord :: MonadWidget t m => TsEvent -> m ()
showRecord TsEvent{..} = do
    el "tr" $ do
        el "td" $ text_ desc
        el "td" $ text $ show eventDate

datePicker :: MonadWidget t m => m ()
datePicker = do
    --cb <- (syncCallback2 AlwaysRetain False $ \x -> print x :: JSFun JSString)
    (e, _) <- elAttr' "div" ("style" =: "width: 250px;") $ return ()
    datePickerElt <- liftIO $ do
        initPikaday $ unElement $ toElement $ _el_element e
        return e
    return ()

stylesheet :: MonadWidget t m => String -> m ()
stylesheet s = elAttr "link" ("rel" =: "stylesheet" <> "href" =: s) blank
