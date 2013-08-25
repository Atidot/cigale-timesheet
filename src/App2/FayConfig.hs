{-# LANGUAGE NoImplicitPrelude, EmptyDataDecls #-}

import Prelude
import FFI
import JQuery

import Utils

data JValue

jvKeys :: JValue -> Fay [String]
jvKeys = ffi "getKeys(%1)"

jvValue :: JValue -> String -> Fay JValue
jvValue = ffi "%1[%2]"

jvArray :: JValue -> Fay [JValue]
jvArray = ffi "%1"

type JvHash = [(String, JValue)]

jvAsHash :: JValue -> Fay JvHash
jvAsHash value = do
	keys <- jvKeys value
	values <- sequence $ map (jvValue value) keys
	return $ zip keys values

-- TODO I would return only Maybe JValue...
-- but somehow I can't make it compile.
-- I think maybe it's because JValue is
-- a phantom type and it has different
-- semantics (notably I shouldn't evaluate it)
jvHashVal :: String -> JvHash -> Maybe (String, JValue)
jvHashVal key hash = find ((==key) . fst) hash -- >>= (Just . snd)

jvGetString :: JValue -> Fay String
jvGetString = ffi "%1"

data ConfigDataInfo = ConfigDataInfo
	{
		memberName :: String,
		memberType :: String
	} deriving (Eq, Show)

data PluginConfig = PluginConfig
	{
		cfgPluginName :: String,
		-- pluginConfig.cfgPluginConfig returns configinfo? stupid naming.
		cfgPluginConfig :: [ConfigDataInfo]
	}

main :: Fay ()
main = ready $ myajax2 "/configVal" "/configdesc" $ \val desc -> handleValDesc (head val) (head desc)

handleValDesc :: JValue -> [PluginConfig] -> Fay ()
handleValDesc configVal pluginConfig = do
	divCurConfig <- select "div#curConfig"
	hash <- jvAsHash configVal
	-- display the user's current config
	forM_ hash (displayPluginConfig pluginConfig divCurConfig)
	-- offer to add new modules
	forM_ pluginConfig addModuleMenuItem

displayPluginConfig :: [PluginConfig] -> JQuery -> (String, JValue) -> Fay ()
displayPluginConfig pluginConfig divCurConfig (pluginName, config) = do
	putStrLn pluginName
	let myPluginConfig = find (\x -> cfgPluginName x == pluginName) pluginConfig
	header <- bootstrapPanel divCurConfig pluginName
	configArray <- jvArray config
	case myPluginConfig of
		Nothing -> putStrLn $ "can't find config info for " ++ pluginName
		Just myP -> do
			forM_ configArray (addPlugin myP header)

addModuleMenuItem :: PluginConfig -> Fay JQuery
addModuleMenuItem pluginConfig = do
	let pluginName = cfgPluginName pluginConfig
	parent <- select "ul#add_module_menu"
	menuItem <- (select $ "<li><a href='#'>" ++ pluginName ++ "</a></li>") >>= appendTo parent
	findSelector "a" menuItem >>= click (\_ -> addEditModuleAction pluginConfig [])

addEditModuleAction :: PluginConfig -> JvHash -> Fay ()
addEditModuleAction pluginConfig existingConfig = do
	let pluginName = cfgPluginName pluginConfig
	modal <- select "#myModal"
	findSelector "div.modal-header h4" modal >>= setText pluginName
	prepareModal (Primary "Save changes") modal
	let configMembers = cfgPluginConfig pluginConfig
	modalContents <- getModalContents configMembers existingConfig
	findSelector "div.modal-body" modal >>= setHtml modalContents
	bootstrapModal modal

data MainAction = Primary String
		  | Danger String
	deriving (Show)

prepareModal :: MainAction -> JQuery -> Fay JQuery
prepareModal action modal = do
	footer <- findSelector "div.modal-footer" modal
	findSelector "#main-action" footer >>= remove
	let btnHtml = "<button type='button' id='main-action' class='btn btn-" ++ btnType ++ "'>" ++ actionText ++ "</button>"
	(select btnHtml) >>= appendTo footer
	where
		(btnType, actionText) = case action of
			Primary x -> ("primary", x)
			Danger x -> ("danger", x)
			_ -> error $ "Unknown action: " ++ (show action)

getModalContents :: [ConfigDataInfo] -> JvHash -> Fay String
getModalContents types configHash = do
		formContents <- sequence $ map (getConfigDataInfoForm configHash) types 
		return $ "<form role='form'><div class='form-group'>"
			++ (foldr (++) [] formContents) ++ "</div></form>"

getConfigDataInfoForm :: JvHash -> ConfigDataInfo -> Fay String
getConfigDataInfoForm configHash dataInfo
	| mType `elem` ["String", "Text", "ByteString"] =
		memberAsString  >>= (return . addTextEntry mName)
	| otherwise = error $ "unknown member type: " ++ mType
	where
		mType = memberType dataInfo
		mName = memberName dataInfo
		memberAsString = case jvHashVal mName configHash of
				Nothing -> return ""
				Just x -> jvGetString $ snd x

addTextEntry :: String -> String -> String
addTextEntry memberName curValue = replace "{}" memberName ("<label for='{}'>{}</label><input type='text'"
				++ " class='form-control' id='{}' placeholder='Enter {}' value='"
				++ curValue ++ "'></div>")

bootstrapModal :: JQuery -> Fay ()
bootstrapModal = ffi "%1.modal('show')"

bootstrapPanel :: JQuery -> String -> Fay JQuery
bootstrapPanel parent title = do
	let panelHtml = "<div class='panel panel-default'><div class='panel-heading'>" ++
		"<h3 class='panel-title'>" ++ title ++ "</h3></div><div class='panel-body'>"
		++ "</div></div>"
	panelRoot <- (select panelHtml) >>= appendTo parent
	findSelector "div.panel-body" panelRoot

bootstrapButton :: String -> String
bootstrapButton name = "<button type='button' class='btn btn-default btn-lg' id='" ++ name ++ "'>"
		++ "<span class='glyphicon glyphicon-" ++ name ++ "'></span></button>"

-- putting XS for the columns because i want a responsive design,
-- that it behaves well when the user reduces the width of the browser
bootstrapWell :: JQuery -> Fay JQuery
bootstrapWell parent = (select $ "<div class='well well-sm'><div class='row'><div class='col-xs-8' id='contents'>"
		++ "</div><div class='col-xs-4'><div class='btn-toolbar' style='float: right;'>" ++ (bootstrapButton "edit")
		++ (bootstrapButton "remove-circle") ++ "</div></div></div>") >>= appendTo parent

addPlugin :: PluginConfig -> JQuery -> JValue -> Fay ()
addPlugin pluginConfig header config = do
	parameterWell <- bootstrapWell header
	parameterContentsDiv <- findSelector "div#contents" parameterWell
	let configDataInfos = cfgPluginConfig pluginConfig
	forM_ configDataInfos (addPluginElement parameterContentsDiv config)
	findSelector "#edit" parameterWell >>= click (\_ -> editConfigItem pluginConfig config)
	findSelector "#remove-circle" parameterWell >>= click (\_ -> deleteConfigItem pluginConfig config)
	return ()

editConfigItem :: PluginConfig -> JValue -> Fay ()
editConfigItem pluginConfig config = jvAsHash config >>= addEditModuleAction pluginConfig

deleteConfigItem :: PluginConfig -> JValue -> Fay ()
deleteConfigItem pluginConfig config = deleteModuleAction pluginConfig

deleteModuleAction :: PluginConfig -> Fay ()
deleteModuleAction pluginConfig = do
	let pluginName = cfgPluginName pluginConfig
	modal <- select "#myModal"
	findSelector "div.modal-header h4" modal >>= setText pluginName
	prepareModal (Danger "Delete") modal
	findSelector "div.modal-body" modal >>= setText "Are you sure you want to delete this data source?"
	bootstrapModal modal

addPluginElement :: JQuery -> JValue -> ConfigDataInfo -> Fay ()
addPluginElement header config dataInfo = do
	let memberNameV = memberName dataInfo
	memberValue <- (jvValue config memberNameV) >>= jvGetString
	(select $ "<div>" ++ memberNameV ++ " " ++ memberValue ++ "</div>") >>= appendTo header
	return ()

-- http://stackoverflow.com/questions/18025474/multiple-ajax-queries-in-parrallel-with-fay
myajax2 :: String -> String -> (Automatic b -> Automatic c -> Fay ()) -> Fay ()
myajax2 = ffi "$.when($.getJSON(%1), $.getJSON(%2)).then(%3)"
