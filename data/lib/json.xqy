(:
Copyright 2011 MarkLogic Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
:)

(:
    TODO:
        Create cts wrappers for the following functions:
        cts:element-child-geospatial-query
        cts:element-geospatial-query
        cts:element-pair-geospatial-query
        cts:element-query
        cts:element-range-query
        cts:element-value-query
        cts:element-word-query
        cts:field-word-query
        cts:word-query
:)

xquery version "1.0-ml";

module namespace json="http://marklogic.com/json";

import module namespace dateparser="http://marklogic.com/dateparser" at "date-parser.xqy";

declare default function namespace "http://www.w3.org/2005/xpath-functions";

(:
    Converts a JSON string into an XML document that is highly indexable by
    MarkLogic. The XML that is generated is intended to be treated like a black
    box. In other words, it isn't something that you're encouraged to use
    directly at this time. However, for those that are brave it is fairly
    resonable to understand.

    $json - A JSON string. This string can contain a number, a string, a
    boolean value, an array or an object.

    Examples:
        json:jsonToXML('3.14159')
        json:jsonToXML('"Hello World')
        json:jsonToXML('true')
        json:jsonToXML('[1, 2, 3, 4]')
        json:jsonToXML('{"foo": "bar"}')
:)
declare function json:jsonToXML(
    $json as xs:string,
    $enableExtensions as xs:boolean
) as element(json:json)
{
    let $tokens := json:tokenize($json)
    let $value := json:parseValue($tokens, 1, (), $enableExtensions)
    let $test :=
        if(xs:integer($value/@position) != count($tokens) + 1)
        then json:outputError($tokens, xs:integer($value/@position), "Unhandled tokens")
        else ()
    return <json:json>{ $value/(@type, @boolean), $value/node() }</json:json>
};

declare function json:jsonToXML(
    $json as xs:string
) as element(json:json)
{
    json:jsonToXML($json, true())
};

(:
    Converts an specially formatted XML document into a JSON string. It is HIGHLY
    important to understand that this function does not accept arbitrary XML.
    It is designed to accept the XML that is generated by the functions in this
    module.

    $element - A XML element that has been generated by the functions in this module

    Examples:
        json:xmlToJSON(json:array((1, 2, 3, 4))) -> "[1, 2, 3, 4]"
:)
declare function json:xmlToJSON(
    $element as element()
) as xs:string
{
    string-join(json:processElement($element), "")
};

(:
    Constructs a JSON document for storage in MarkLogic.

    $value - A JSON item (see below for a description of what a JSON item can be).

    Examples:
        json:document(3.14159)
        json:document("Hello World")
        json:document(true())
        json:document(json:array((1, 2, 3, 4)))
        json:document(json:object(("foo", "bar")))


    A word on JSON items.
    The various functions in this module that accept JSON items (json:document,
    json:object and json:array) examine the type of the passed in item and
    convert it to the appropriate JSON type.

    Here's how the casting works, most are obvious:
    • XQuery string -> JSON string
    • XQuery boolean -> JSON boolean
    • XQuery integer or decimal -> JSON number
    • Every other XQuery type -> JSON string

    A JSON item may also be the result return value of json:array or json:object.
:)
declare function json:document(
    $value as item()
) as element(json:json)
{
    <json:json version="1.0">{
        json:untypedToJSONType($value)/(@*, node())
    }</json:json>
};

(:
    Constructs a JSON object in an XML format for use in json:document,
    json:array or json:xmlToJSON. The return value is not a string but a JSON
    item. For more information on JSON items, see the note in json:document.

    There are also a convenience function json:o.

    $keyValues - A sequence of alternating object keys and values. The keys
        must be strings and the values can be JSON items. Keys must be unique.

    Examples:
        json:object(("foo", "bar")) -> {"foo": "bar"}
        json:object(("foo", json:array((1, 2, 3, 4)))) - > {"foo": [1, 2, 3, 4]}
        json:object(("foo", true(), "bar", false())) -> {"foo": true, "bar": false}
:)
declare function json:object(
    $keyValues as item()*
) as element(json:item)
{
    let $keys := map:map()
    let $check :=
        for $i at $pos in $keyValues
        where $pos mod 2 != 0
        return (
            if(not($i castable as xs:string))
            then error(xs:QName("json:OBJECTKEY"), concat("The object key at location ", ceiling($pos div 2), " isn't a string"))
            else (),
            if(map:get($keys, string($i)))
            then error(xs:QName("json:OBJECTKEY"), concat("The object key at location ", ceiling($pos div 2), " is a duplicate"))
            else (),
            map:put($keys, string($i), true())
        )
    return
        <json:item type="object">{
            for $key at $pos in $keyValues
            return
                if($pos mod 2 != 0)
                then element { xs:QName(concat("json:", json:escapeNCName($key))) } { json:untypedToJSONType($keyValues[$pos + 1])/(@*, node()) }
                else ()
        }</json:item>
};

declare function json:o(
    $keyValues as item()*
) as element(json:item)
{
    json:object($keyValues)
};

declare function json:object(
) as element(json:item)
{
    json:object(())
};

declare function json:o(
) as element(json:item)
{
    json:object(())
};

(:
    Constructs a JSON array in an XML format for use in json:document,
    json:object or json:xmlToJSON. The return value is not a string but a JSON
    item. For more information on JSON items, see the note in json:document.

    There are also a convenience function json:a.

    $items - A sequence of JSON items to include in the array.

    Examples:
        json:array((1, 2, 3, 4)) -> [1, 2, 3, 4]
        json:array((true(), false(), "foo")) -> [true, false, "foo"]
        json:array((json:object(("foo", "bar")), json:object(("baz", "yaz")))) -> [{"foo": "bar"}, {"baz": "yaz"}]
:)
declare function json:array(
    $items as item()*
) as element(json:item)
{
    <json:item type="array">{
        for $item in $items
        return json:untypedToJSONType($item)
    }</json:item>
};

declare function json:a(
    $items as item()*
) as element(json:item)
{
    json:array($items)
};

declare function json:array(
) as element(json:item)
{
    json:array(())
};

declare function json:a(
) as element(json:item)
{
    json:array(())
};

(:
    Because JSON doesn't have a date datatype, we have to do some special
    things. This function will accept either an xs:dateTime, xs:date or a date
    string.  In the case of a date string, an attempt will be made to parse the
    string into an xs:dateTime.  If the string cannot be parsed an error is thrown.
:)
declare function json:date(
    $value as xs:anySimpleType
) as element(json:item)
{
    let $value :=
        if($value instance of xs:dateTime or $value instance of xs:date)
        then string($value)
        else if($value instance of xs:string)
        then $value
        else error(xs:QName("json:INVALID-DATE"), concat("Invalid date: ", xdmp:quote($value)))
    let $date := dateparser:parse($value)
    return
        if(empty($date))
        then error(xs:QName("json:INVALID-DATE"), concat("Invalid date: ", $value))
        else <json:item normalized-date="{ $date }" type="date">{ $value }</json:item>
};

(:
    Because JSON doesn't have an xml datatype, we have to do some special
    things to get it to work.  When serialized out as JSON the xml will appear
    as a string but internally it is represented as an xml tree.
:)
declare function json:xml(
    $value as element()
) as element(json:item)
{
    <json:item type="xml">{ $value }</json:item>
};

(:
    Because XQuery doesn't have a stict null value, this function allows us to
    construct a JSON null. This can be useful if you need objects or arrays
    with null values.

    Examples:
        json:array((1, 2, json:null(), 4)) -> [1, 2, null, 4]
        json:object(("foo", json:null())) -> {"foo": null}
:)
declare function json:null(
) as element(json:item)
{
    <json:item type="null"/>
};


(: Search functions :)

declare function json:rangeIndexValues(
    $key as xs:string,
    $type as xs:string,
    $query as cts:query?,
    $options as xs:string*,
    $limit as xs:integer?
) as xs:anyAtomicType*
{
    let $options := (
        if(exists($limit))
        then concat("limit=", $limit)
        else (),
        $options
    )
    let $key := xs:QName(concat("json:", json:escapeNCName($key)))
    return
        if($type = "date")
        then cts:element-attribute-values($key, xs:QName("normalized-date"), (), ("type=dateTime", $options), $query)
        else if($type = "string")
        then cts:element-values($key, (), ("type=string", $options), $query)
        else if($type = "number")
        then cts:element-values($key, (), ("type=decimal", $options), $query)
        else ()
};


(:
    Private functions
:)
declare private function json:untypedToJSONType(
    $value as item()?
) as element(json:item)
{
    <json:item>{
        if(exists($value))
        then
            if($value instance of element(json:item) or $value instance of element(json:json))
            then $value/(@*, node())

            else if($value instance of xs:boolean and $value = true())
            then attribute boolean { "true" }
            else if($value instance of xs:boolean and $value = false())
            then attribute boolean { "false" }

            else if($value instance of xs:integer or $value instance of xs:decimal)
            then (attribute type { "number" }, string($value))

            else if($value instance of xs:string)
            then (attribute type { "string" }, string($value))

            else (attribute type { "string" }, xdmp:quote($value))
        else attribute type { "null" }
    }</json:item>
};

declare private function json:parseValue(
    $tokens as element(token)*,
    $position as xs:integer,
    $castAs as xs:string?,
    $enableExtensions as xs:boolean
) as element(value)
{
    let $token := $tokens[$position]
    let $value :=
        if($token/@t = "lbrace")
        then json:parseObject($tokens, $position + 1, $enableExtensions)

        else if($token/@t = "lsquare")
        then json:parseArray($tokens, $position + 1, $castAs, $enableExtensions)

        else if($token/@t = "number")
        then <value type="number" position="{ $position + 1 }">{ string($token) }</value>

        else if($token/@t = "string")
        then
            let $string := json:unescapeJSONString($token)
            return
                if(empty($castAs) or $enableExtensions = false())
                then <value type="string" position="{ $position + 1 }">{ $string }</value>
                else if($castAs = "xml")
                then <value type="xml" position="{ $position + 1 }">{
                    try {
                        xdmp:unquote($string)
                    }
                    catch ($e) {
                        json:outputError($tokens, $position, "The string was told to be treated as XML however, it isn't valid XML")
                    }
                }</value>
                else if($castAs = "date")
                then <value type="date" position="{ $position + 1 }">{
                    let $parsed := dateparser:parse($string)
                    return
                        if(exists($parsed))
                        then (
                            attribute normalized-date { $parsed },
                            $string
                        )
                        else json:outputError($tokens, $position, concat("The string ", $string, " was told to be treated as a date however, it couldn't be parsed"))
                }</value>
                else <value type="string" position="{ $position + 1 }">{ $string }</value>

        else if($token/@t = "true" or $token/@t = "false")
        then <value boolean="{ $token }" position="{ $position + 1 }"/>

        else if($token/@t = "null")
        then <value type="null" position="{ $position + 1 }"/>

        else json:outputError($tokens, $position, "Expected an object, array, string, number, boolean or null")

    return $value
};

declare private function json:parseArray(
    $tokens as element(token)*,
    $position as xs:integer,
    $castAs as xs:string?,
    $enableExtensions as xs:boolean
) as element(value)
{
    let $finalLocation := $position
    let $items :=
        let $foundClosingBracket := false()

        for $index in ($position to count($tokens))
        where $foundClosingBracket = false() and $index >= $finalLocation
        return
            if($tokens[$index]/@t = "rsquare")
            then (
                xdmp:set($foundClosingBracket, true()),
                xdmp:set($finalLocation, $index + 1)
            )

            else if($tokens[$index]/@t = "comma")
            then xdmp:set($finalLocation, $index)

            else
                let $test := json:shouldBeOneOf($tokens, $index, ("lbrace", "lsquare", "string", "number", "true", "false", "null"), "Expected an array, object, string, number, boolean or null")
                let $value := json:parseValue($tokens, $index, $castAs, $enableExtensions)
                let $set := xdmp:set($finalLocation, xs:integer($value/@position))
                let $test := json:shouldBeOneOf($tokens, $finalLocation, ("comma", "rsquare"), "Expected either a comma or closing array")
                return <json:item>{ $value/(@type, @boolean, @normalized-date), $value/node() }</json:item>

    return <value type="array" position="{ $finalLocation }">{ $items }</value>
};

declare private function json:parseObject(
    $tokens as element(token)*,
    $position as xs:integer,
    $enableExtensions as xs:boolean
) as element(value)
{
    if($tokens[$position + 1]/@t = "rbrace")
    then <value type="object" position="{ $position + 1 }"/>
    else

    let $finalLocation := $position
    let $items :=
        let $foundClosingBrace := false()

        for $index in ($position to count($tokens))
        where $foundClosingBrace = false() and $index >= $finalLocation
        return
            if($tokens[$index]/@t = "rbrace")
            then (
                xdmp:set($foundClosingBrace, true()),
                xdmp:set($finalLocation, $index + 1)
            )

            else if($tokens[$index]/@t = "comma")
            then xdmp:set($finalLocation, $index)

            else
                let $test := json:shouldBeOneOf($tokens, $index, "string", "Expected an object key")
                let $test := json:shouldBeOneOf($tokens, $index + 1, "colon", "Expected a colon")
                let $test := json:shouldBeOneOf($tokens, $index + 2, ("lbrace", "lsquare", "string", "number", "true", "false", "null"), "Expected an array, object, string, number, boolean or null")

                let $key := json:escapeNCName($tokens[$index])
                let $castAs := json:castAs($tokens[$index], $enableExtensions)
                let $value := json:parseValue($tokens, $index + 2, $castAs, $enableExtensions)
                let $set := xdmp:set($finalLocation, xs:integer($value/@position))
                let $test := json:shouldBeOneOf($tokens, $finalLocation, ("comma", "rbrace"), "Expected either a comma or closing object")

                return element { xs:QName(concat("json:", $key)) } { $value/(@type, @boolean, @normalized-date), $value/node() }

    return <value type="object" position="{ $finalLocation }">{ $items }</value>
};


declare private function json:shouldBeOneOf(
    $tokens as element(token)*,
    $index as xs:integer,
    $types as xs:string+,
    $expectedMessage as xs:string
) as empty-sequence()
{
    if($tokens[$index]/@t = $types)
    then ()
    else json:outputError($tokens, $index, $expectedMessage)
};

declare private function json:outputError(
    $tokens as element(token)*,
    $index as xs:integer,
    $expectedMessage as xs:string
) as empty-sequence()
{
    let $context := string-join(
        let $contextTokens := $tokens[$index - 3 to $index + 4]
        let $valueTokenTypes := ("string", "number", "true", "false", "null")
        for $token at $loc in $contextTokens
        let $value :=
            if($token/@t = "string")
            then concat('"', string($token), '"')
            else string($token)
        return
            if($token/@t = ("comma", "colon"))
            then concat($value, " ")
            else if($token/@t = $valueTokenTypes and $contextTokens[$loc + 1]/@t = $valueTokenTypes)
            then concat($value, " ")
            else $value
    , "")
    return error(xs:QName("json:PARSE01"), concat("Unexpected token ", string($tokens[$index]/@t), ": '", $context, "'. ", $expectedMessage))
};

declare private function json:unescapeJSONString($val as xs:string)
  as xs:string
{
    string-join(
        let $regex := '[^\\]+|(\\")|(\\\\)|(\\/)|(\\b)|(\\f)|(\\n)|(\\r)|(\\t)|(\\u[A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9])'
        for $match in analyze-string($val, $regex)/*
        return 
            if($match/*:group/@nr = 1) then """"
            else if($match/*:group/@nr = 2) then "\"
            else if($match/*:group/@nr = 3) then "/"
            (: else if($match/*:group/@nr = 4) then "&#x08;" :)
            (: else if($match/*:group/@nr = 5) then "&#x0C;" :)
            else if($match/*:group/@nr = 6) then "&#x0A;"
            else if($match/*:group/@nr = 7) then "&#x0D;"
            else if($match/*:group/@nr = 8) then "&#x09;"
            else if($match/*:group/@nr = 9) then codepoints-to-string(xdmp:hex-to-integer(substring($match, 3)))
            else string($match)
    , "")
};

declare private function json:tokenize(
    $json as xs:string
) as element(token)*
{
    let $tokens := ("\{", "\}", "\[", "\]", ":", ",", "true", "false", "null", "\s+",
        '"([^"\\]|\\"|\\\\|\\/|\\b|\\f|\\n|\\r|\\t|\\u[A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9])*"',
        "-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?")
    let $regex := string-join(for $t in $tokens return concat("(",$t,")"),"|")
    for $match in analyze-string($json, $regex)/*
    return
        if($match/self::*:non-match) then json:createToken("error", string($match))
        else if($match/*:group/@nr = 1) then json:createToken("lbrace", string($match))
        else if($match/*:group/@nr = 2) then json:createToken("rbrace", string($match))
        else if($match/*:group/@nr = 3) then json:createToken("lsquare", string($match))
        else if($match/*:group/@nr = 4) then json:createToken("rsquare", string($match))
        else if($match/*:group/@nr = 5) then json:createToken("colon", string($match))
        else if($match/*:group/@nr = 6) then json:createToken("comma", string($match))
        else if($match/*:group/@nr = 7) then json:createToken("true", string($match))
        else if($match/*:group/@nr = 8) then json:createToken("false", string($match))
        else if($match/*:group/@nr = 9) then json:createToken("null", string($match))
        else if($match/*:group/@nr = 10) then () (:ignore whitespace:)
        else if($match/*:group/@nr = 11) then
            let $v := string($match)
            let $len := string-length($v)
            return json:createToken("string", substring($v, 2, $len - 2))
        else if($match/*:group/@nr = 13) then json:createToken("number", string($match))
        else json:createToken("error", string($match))
};

declare private function json:createToken(
    $type as xs:string,
    $value as xs:string
) as element(token)
{
    <token t="{ $type }">{ $value }</token>
};




declare private function json:processElement(
    $element as element()
) as xs:string*
{
    if($element/@type = "object") then json:outputObject($element)
    else if($element/@type = "array") then json:outputArray($element)
    else if($element/@type = "null") then "null"
    else if(exists($element/@boolean)) then xs:string($element/@boolean)
    else if($element/@type = "number") then xs:string($element)
    else if($element/@type = "xml") then ('"', json:escapeJSONString(xdmp:quote(<remove_json_ns>{ $element/* }</remove_json_ns>/*)), '"')
    else ('"', json:escapeJSONString($element), '"')
};

declare private function json:outputObject(
    $element as element()
) as xs:string*
{
    "{",
        for $child at $pos in $element/json:*
        return (
            if($pos = 1)
            then ()
            else ","
            ,
            '"', json:unescapeNCName(local-name($child)), '":', json:processElement($child)
        ),
    "}"
};

declare private function json:outputArray(
    $element as element()
) as xs:string*
{
    "[",
        for $child at $pos in $element/json:item
        return (
            if($pos = 1)
            then ()
            else ","
            ,
            json:processElement($child)
        ),
    "]"
};

(: Need to backslash escape any double quotes, backslashes, and newlines :)
declare private function json:escapeJSONString(
    $string as xs:string
) as xs:string
{
    let $string := replace($string, "\\", "\\\\")
    let $string := replace($string, """", "\\""")
    let $string := replace($string, codepoints-to-string((13, 10)), "\\n")
    let $string := replace($string, codepoints-to-string(13), "\\n")
    let $string := replace($string, codepoints-to-string(10), "\\n")
    let $string := replace($string, codepoints-to-string(9), "\\t")
    return $string
};

declare private function json:encodeHexStringHelper(
    $num as xs:integer,
    $digits as xs:integer
) as xs:string*
{
    if($digits > 1)
    then json:encodeHexStringHelper($num idiv 16, $digits - 1)
    else (),
    ("0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F")[$num mod 16 + 1]
};

declare function json:escapeNCName(
    $val as xs:string
) as xs:string
{
    if($val = "")
    then "_"
    else
        string-join(
            let $regex := ':|_|(\i)|(\c)|.'
            for $match at $pos in analyze-string($val, $regex)/*
            return
                if($match/*:group/@nr = 1 or ($match/*:group/@nr = 2 and $pos != 1))
                then string($match)
                else ("_", json:encodeHexStringHelper(string-to-codepoints($match), 4))
        , "")
};

declare function json:unescapeNCName(
    $val as xs:string
) as xs:string
{
    if($val = "_")
    then ""
    else
        string-join(
            let $regex := '(_[A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9])|[^_]+'
            for $match at $pos in analyze-string($val, $regex)/*
            return
                if($match/*:group/@nr = 1)
                then codepoints-to-string(xdmp:hex-to-integer(substring($match, 2)))
                else string($match)
      , "")
};

declare function json:castAs(
    $key as xs:string,
    $enableExtensions as xs:boolean
) as xs:string?
{
    let $keyBits :=
        if($enableExtensions)
        then tokenize($key, "::")
        else $key
    return
        if(count($keyBits) > 1)
        then $keyBits[last()][. = ("xml", "date")]
        else ()
};
