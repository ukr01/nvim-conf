; extends

((request
  header: (header
    name: (header_entity) @_header_name
    value: (value) @_header_value)
  body: (raw_body) @injection.content)
  (#match? @_header_name "^[Cc]ontent-[Tt]ype$")
  (#match? @_header_value "application/[A-Za-z0-9.+-]*json")
  (#set! injection.language "json"))
