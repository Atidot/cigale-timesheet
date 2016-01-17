{-# LANGUAGE ScopedTypeVariables, LambdaCase, OverloadedStrings, JavaScriptFFI, ForeignFunctionInterface, RecordWildCards #-}

module Common where

import GHCJS.Types
import GHCJS.Foreign
import GHCJS.DOM.Element
import GHCJS.DOM.Types hiding (Text, Event)

import Reflex.Dom
import Data.Dependent.Sum (DSum ((:=>)))
import Reflex.Host.Class
import Data.String

import Data.Maybe
import Data.IORef
import Data.Text (Text)
import qualified Data.Text as T
import Data.Monoid
import Data.Map (Map)
import Control.Monad.IO.Class
import Data.Aeson
import Control.Monad

data ActiveView = ActiveViewEvents | ActiveViewConfig deriving (Eq, Show)

foreign import javascript unsafe "$($1).modal('hide')" _hideModalDialog :: JSRef Element -> IO ()
hideModalDialog :: ModalDialogResult t a -> IO ()
hideModalDialog = _hideModalDialog . unwrapElt . modalElt

foreign import javascript unsafe "$($1).modal('show')" _showModalDialog :: JSRef Element -> IO ()
showModalDialog :: ModalDialogResult t a -> IO ()
showModalDialog = _showModalDialog . unwrapElt . modalElt

foreign import javascript unsafe
    "$($1).on('hidden.bs.modal', $2)"
    onModalHidden :: JSRef Element -> JSFun(IO ()) -> IO ()

unwrapElt :: El t -> JSRef Element
unwrapElt = unElement . toElement . _el_element

eltStripClass :: IsElement self => self -> Text -> IO ()
eltStripClass elt className = do
    curClasses <- T.splitOn " " <$> T.pack <$> elementGetClassName elt
    let newClasses = T.unpack <$> filter (/= className) curClasses
    elementSetClassName elt (unwords newClasses)

attrOptDyn :: a -> String -> Bool -> String -> Map a String
attrOptDyn attr opt p s = attr =: (s <> if p then " " <> opt else "")

styleWithHideIf :: Bool -> String -> Map String String
styleWithHideIf p s = "style" =: (rest <> if p then "display: none" else "display: block")
    where rest = if null s then "" else s <> "; "

styleHideIf :: Bool -> Map String String
styleHideIf p = styleWithHideIf p ""

stylesheet :: MonadWidget t m => String -> m ()
stylesheet s = elAttr "link" ("rel" =: "stylesheet" <> "href" =: s) blank

text_ :: MonadWidget t m => Text -> m ()
text_ = text . T.unpack

performOnChange :: MonadWidget t m => (a -> WidgetHost m ()) -> Dynamic t a -> m ()
performOnChange action dynamic = performEvent_ $
    fmap (const $ sample (current dynamic) >>= action) $ updated dynamic

button' :: MonadWidget t m => String -> m (Event t ())
button' s = do
  (e, _) <- elAttr' "button" ("class" =: "btn btn-secondary btn-sm") $ text s
  return $ domEvent Click e

-- very similar to fireEventRef from Reflex.Host.Class
-- which I don't have right now.
-- #reflex-frp on freenode.net, 2015-12-25:
-- [21:38] <ryantrinkle> the only thing you might want to improve later
--         is that you could make it so that it subscribes to the event lazily
-- [21:39] <ryantrinkle> and it unsubscribes when the event gets garbage collected
-- [21:39] <ryantrinkle> https://hackage.haskell.org/package/reflex-dom-0.2/docs/src/Reflex-Dom-Widget-Basic.html#wrapDomEventMaybe
handleTrigger :: MonadIO m => ([DSum tag] -> m ()) -> a -> IORef (Maybe (tag a)) -> m ()
handleTrigger runWithActions v trigger = liftIO (readIORef trigger) >>= \case
        Nothing       -> return ()
        Just eTrigger -> runWithActions [eTrigger :=> v]

data ModalDialogResult t a = ModalDialogResult
     {
         modalElt      :: El t,
         bodyResult    :: Dynamic t a,
         okBtnEvent    :: Event t (),
         closeBtnEvent :: Event t (),
         closedEvent   :: Event t ()
     }

data ButtonInfo = PrimaryBtn String | DangerBtn String

buildModalDialog :: MonadWidget t m => String -> ButtonInfo -> Event t ()
                 -> Event t String -> m a -> m (ModalDialogResult t a)
buildModalDialog title okBtnInfo showEvent _errorEvent contents = do
    -- whenever the user opens the modal, clear the error display.
    let errorEvent = leftmost [_errorEvent, const "" <$> showEvent]
    let (okBtnText, okBtnClass) = case okBtnInfo of
            PrimaryBtn txt -> (txt, "primary")
            DangerBtn txt -> (txt, "danger")
    -- for tabindex=-1, see http://stackoverflow.com/a/12630531/516188
    (modalDiv, (br, oke, ce)) <- elAttr' "div" ("class" =: "modal fade" <> "tabindex" =: "-1") $
        elAttr "div" ("class" =: "modal-dialog" <> "role" =: "document") $
            elAttr "div" ("class" =: "modal-content") $ do
                elAttr "div" ("class" =: "modal-header") $ do
                    void $ elAttr "button" ("type" =: "button" <> "class" =: "close"
                                    <> "data-dismiss" =: "modal" <> "aria-label" =: "Close") $
                        elDynHtmlAttr' "span" ("aria-hidden" =: "true") (constDyn "&times;")
                    elAttr "h4" ("class" =: "modal-title") $ text title
                bodyRes <- elAttr "div" ("class" =: "modal-body") $ do
                    dynErrMsg <- holdDyn "" errorEvent
                    dynAttrs <- mapDyn (\errMsg ->
                                         "class" =: "alert alert-danger"
                                         <> "role" =: "alert"
                                         <> styleHideIf (null errMsg)) dynErrMsg
                    elDynAttr "div" dynAttrs $ do
                        elAttr "strong" ("style" =: "padding-right: 7px") $ text "Error"
                        dynText dynErrMsg
                    -- for "form entry" modals, we must regenerate the modal html
                    -- everytime the user wants to display it.
                    -- Example: open modal, edit contents, cancel.
                    -- You don't want to see the discarded values when reopening.
                    widgetHold contents (fmap (const contents) showEvent)
                (okEvt, closeEvt)  <- elAttr "div" ("class" =: "modal-footer") $ do
                    (closeEl, _) <- elAttr' "button" ("type" =: "button"
                                                      <> "class" =: "btn btn-secondary"
                                                      <> "data-dismiss" =: "modal")
                        $ text "Close"
                    (okEl, _) <- elAttr' "button" ("type" =: "button"
                                                   <> "class" =: ("btn btn-" <> okBtnClass))
                        $ text okBtnText
                    return (domEvent Click okEl, domEvent Click closeEl)
                return (bodyRes, okEvt, closeEvt)
    -- now prepare the event for when the dialog gets closed
    (closedEvent, closedEvtTrigger) <- newEventWithTriggerRef
    postGui <- askPostGui
    runWithActions <- askRunWithActions
    liftIO $ do
        hiddenCb <- syncCallback AlwaysRetain False $
            postGui $ handleTrigger runWithActions () closedEvtTrigger
        onModalHidden (unwrapElt modalDiv) hiddenCb
    let dialogInfo = ModalDialogResult modalDiv br oke ce closedEvent
    performEvent_ $ fmap (const $ liftIO $ showModalDialog dialogInfo) showEvent
    return dialogInfo

data RemoteData a = RemoteDataInvalid String | RemoteDataLoading | RemoteData a deriving Show

instance Functor RemoteData where
    fmap _ RemoteDataLoading = RemoteDataLoading
    fmap _ (RemoteDataInvalid x) = RemoteDataInvalid x
    fmap f (RemoteData a) = RemoteData (f a)

instance Applicative RemoteData where
    pure = RemoteData
    RemoteData f <*> r = fmap f r
    (RemoteDataInvalid x) <*> _ = RemoteDataInvalid x
    RemoteDataLoading <*> _ = RemoteDataLoading

instance Monad RemoteData where
    (RemoteDataInvalid x) >>= _ = RemoteDataInvalid x
    RemoteDataLoading >>= _ = RemoteDataLoading
    RemoteData x >>= f = f x

readEmptyRemoteData :: XhrResponse -> RemoteData ()
readEmptyRemoteData XhrResponse{..} = case _xhrResponse_status of
    200 -> case _xhrResponse_body of
        Nothing -> RemoteData ()
        Just "" -> RemoteData ()
        Just x -> RemoteDataInvalid $ "Expected empty response, got" <> T.unpack x
    _ -> RemoteDataInvalid $ "HTTP response code " <> show _xhrResponse_status
             <> "; details: " <> T.unpack (fromMaybeEmpty "none" _xhrResponse_body)

readRemoteData :: FromJSON a => XhrResponse -> RemoteData a
readRemoteData XhrResponse{..} = case _xhrResponse_status of
    200 -> case _xhrResponse_body of
        Nothing -> RemoteDataInvalid "Empty server response"
        Just rawData -> case decodeText rawData of
            Nothing -> RemoteDataInvalid $
                "JSON has invalid format: " <> T.unpack (fromMaybe "Nothing" _xhrResponse_body)
            Just decoded -> RemoteData decoded
    _ -> RemoteDataInvalid $ "HTTP response code " <> show _xhrResponse_status
             <> "; details: " <> T.unpack (fromMaybeEmpty "none" _xhrResponse_body)

fromMaybeEmpty :: (IsString a, Eq a) => a -> Maybe a -> a
fromMaybeEmpty val Nothing = val
fromMaybeEmpty val (Just "") = val
fromMaybeEmpty _ (Just r) = r

isRemoteDataLoading :: RemoteData a -> Bool
isRemoteDataLoading RemoteDataLoading = True
isRemoteDataLoading _ = False

remoteDataInvalidDesc :: RemoteData a -> Maybe String
remoteDataInvalidDesc (RemoteDataInvalid x) = Just x
remoteDataInvalidDesc _ = Nothing

fromRemoteData :: RemoteData a -> Maybe a
fromRemoteData (RemoteData x) = Just x
fromRemoteData _ = Nothing

makeSimpleXhr :: (MonadWidget t m, FromJSON a) => String -> Event t b -> m (Dynamic t (RemoteData a))
makeSimpleXhr url = makeSimpleXhr' (const url)

makeSimpleXhr' :: (MonadWidget t m, FromJSON a) => (b -> String) -> Event t b -> m (Dynamic t (RemoteData a))
makeSimpleXhr' getUrl evt = do
    req <- performRequestAsync $ (\evtVal -> xhrRequest "GET" (getUrl evtVal) def) <$> evt
    holdDyn RemoteDataLoading $ fmap readRemoteData req
