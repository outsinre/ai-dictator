-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "ai-dictator"


local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          {
            model_name = {
              type = "string",
              required = true,
              one_of = { "gpt-4o-mini", "gpt-4o", "o1-mini", "deepseek-r1" },
              default = "deepseek-r1"
            }
          },
          {
            api_key = {
              type = "string",
              required = true,
              default = nil
            }
          },
          {
            body_key = typedefs.header_name {
              required = true,
              default = "X-Body-Key" }
          },
          {
            request_header = typedefs.header_name {
              required = true,
              default = "X-Ping" }
          },
          {
            response_header = typedefs.header_name {
              required = true,
              default = "X-Pong" }
          },
        },
        entity_checks = {
          { at_least_one_of = { "body_key", "request_header", "response_header" }, },
          { distinct = { "body_key", "request_header", "response_header" } },
        },
      },
    },
  },
}

return schema
