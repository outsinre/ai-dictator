-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


--[=[
gpt-4o-mini
gpt-4o
o1-mini
deepseek-r1

curl -v 'https://hackathonchina2025.services.ai.azure.com/models/chat/completions' \
-H "api-key: $AI_API_KEY" \
-H "content-type: application/json" \
-d '{"model":"gpt-4o", "messages":[{"role": "user", "content": "Could you tell me if the word foolish is elegant in public place? Please answer with Yes or NO"}],"stream":false}' \

# -H "content-type: application/json" is optional
curl -v localhost:8000/anything \
-d '{ "jim": "You just asked a stupid question.", "gray": "He is a very nice person." }' \
-H "X-Body-Key: jim"

curl -v localhost:8000/anything
curl -v localhost:8000/anything -d '{}'

curl -v localhost:8000/anything -d 'null'
curl -v localhost:8000/anything -d 'false'
curl -v localhost:8000/anything -d '123'
curl -v localhost:8000/anything \
-d '"We had the Hackathon 2025 event yesterday. Women performed better than men."'

curl -v localhost:8000/anything -d 'x=123'
]=]


local cjson     = require("cjson.safe").new()
local pl_tablex = require "pl.tablex"
local kong_meta = require "kong.meta"
local http      = require "resty.http"


local kong        = kong
local type        = type
local next        = next
local tostring    = tostring
local json_decode = cjson.decode
local json_encode = cjson.encode
local str_lower   = string.lower


local EMPTY_T = pl_tablex.readonly({})
local DEFAULT_BODY_KEY = "message"
local DEFAULT_MODEL_NAME = "deepseek-r1"
local DEFAULT_TIMEOUT = 60000


local AIDictatorHandler = {
  PRIORITY = 1300,
  VERSION = kong_meta.core_version,
}


local function get_json_body()
  ngx.req.read_body()
  local body_data = ngx.req.get_body_data()

  if not body_data then
    --no raw body, check temp body
    local body_file = ngx.req.get_body_file()
    if body_file then
      local file, err = io.open(body_file, "r")
      if not file then
        return nil, "failed to open body temp file: " .. err
      end

      body_data = file:read("*all")
      file:close()
    end
  end

  if not body_data or #body_data == 0 then
    kong.log.warn("request body not found, default to empty JSON object")
    return EMPTY_T
  end

  local json_body, err = json_decode(body_data)
  if err then
    return nil, "request body not valid JSON"
  end

  -- userdata null, boolean, number, string
  if type(json_body) ~= "table" then
    kong.log.warn("request body is a primitive JSON value, using default key '" .. DEFAULT_BODY_KEY .. "'")
    return { [DEFAULT_BODY_KEY] = tostring(json_body) }
  end

  if not next(json_body) then
    kong.log.warn("request body empty JSON object")
  end

  return json_body
end


local function ai_decision(model_name, api_key, message)
  if message == nil or message == "" then
    return "No"
  end

  local model_name = model_name or DEFAULT_MODEL_NAME

  local httpc = http.new()
  httpc:set_timeouts(DEFAULT_TIMEOUT, DEFAULT_TIMEOUT, DEFAULT_TIMEOUT)

  local url = "https://hackathonchina2025.services.ai.azure.com/models/chat/completions"

  local headers = {
    ["API-Key"] = api_key,
    ["Content-Type"] = "application/json",
    ["Cache-Control"] = "no-cache, no-store, must-revalidate",
    ["Pragma"] = "no-cache",
    ["Expires"] = "0",
  }

  local content = "Given the text enclosed in the XML tags <txt> and </txt> as follows. " ..
      "Could you tell me if there exist negative, inelegant, polictical incorrect, offensive contents? " ..
      "Please answer with 'Yes' or 'No'. When answering the question, please kindly be reminded that " ..
      "the text may be presented to pulbic audience, including teenage.\n" ..
      "<txt>" .. message .. "</txt>"
  local request_body = {
    model = model_name,
    messages = {
      { role = "system", content = "You are a smart assistant" },
      { role = "user",   content = content },
    },
    stream = false,
  }

  local res, err = httpc:request_uri(url, {
    method = "POST",
    headers = headers,
    body = json_encode(request_body),
    ssl_verify = false,
  })

  if not res then
    local err_msg = model_name ..  " AI request failed: " .. err
    kong.log.err(err_msg)
    return kong.response.exit(500, { message = err_msg })
  end

  local response_data
  response_data, err = json_decode(res.body)
  if not response_data then
    local err_msg = model_name .. " AI response is not valid JSON: " .. err
    kong.log.err(err_msg)
    return kong.response.exit(500, { message = err_msg })
  end

  if res.status ~= 200 then
    local err_msg = model_name .. " AI error response: " .. response_data.error.message
    kong.log.err(err_msg)
    return kong.response.exit(res.status, { message = err_msg })
  end

  return response_data.choices[1].message.content
end


function AIDictatorHandler:access(plugin_conf)
  local json_body, err = get_json_body()
  if err then
    kong.log.err(err)
    return kong.response.exit(400, { message = err })
  end

  if not json_body or not next(json_body) then
    return true
  end

  local body_key = kong.request.get_header(plugin_conf.body_key)
  if not body_key then
    kong.log.warn("key not found in header '" .. plugin_conf.body_key .. "', default to '" .. DEFAULT_BODY_KEY .. "'")
    body_key = DEFAULT_BODY_KEY
  end

  local model_name = plugin_conf.model_name or DEFAULT_MODEL_NAME
  local rc
  rc, err = ai_decision(model_name,
                        plugin_conf.api_key,
                        tostring(json_body[body_key]))

  if rc then
    if str_lower(rc) == "yes" then
      kong.response.exit(400, { message = model_name .. " AI decision: request inelegant" })

    else
      kong.log(model_name .. " AI decision: ", rc)
    end

  else
    return kong.response.exit(500, { message = model_name .. " AI decision error: " .. err })
  end

  kong.service.request.set_header(plugin_conf.request_header, "dir 1")
end

function AIDictatorHandler:header_filter(plugin_conf)
  kong.response.set_header(plugin_conf.response_header, "dir 3")
end

function AIDictatorHandler:log(plugin_conf)
  kong.log(plugin_conf.model_name)
  kong.log(plugin_conf.body_key)
end

return AIDictatorHandler
