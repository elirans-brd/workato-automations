{
  title: 'Bright Data All-in-One Connector',

  # -------------------------------------------------------------------------
  # CONNECTION BLOCK
  # Handles authentication via Bearer token.
  # The token is taken from the user's Bright Data control panel and injected
  # into every request header automatically.
  # -------------------------------------------------------------------------
  connection: {
    authorization: {
      type: "custom_auth",
      apply: lambda do |connection|
        headers('Authorization': "Bearer #{connection['api_token']}")
      end
    },
    fields: [
      {
        name: "api_token",
        label: "API Token",
        optional: false,
        hint: "Provide the API Key or Bearer Token found in your Bright Data control panel.<br/>" \
              "For more information on how to create a connection to Bright Data, see the " \
              "<a href='https://docs.brightdata.com/api-reference/authentication' target='_blank'>API Reference</a>.",
        control_type: "password",
        sensitive: true
      }
    ],
    extended_fields: lambda do |connection|
      []
    end,
    base_uri: lambda do |connection|
      'https://api.brightdata.com/'
    end,
    description: "For more information on how to create a connection to Bright Data, see the " \
                 "<a href='https://docs.brightdata.com/api-reference/authentication' target='_blank'>API Reference</a>."
  },

  # -------------------------------------------------------------------------
  # TEST BLOCK
  # Validates the connection by calling the zones endpoint.
  # If the API token is invalid this call will fail and Workato will surface
  # the error to the user during connection setup.
  # -------------------------------------------------------------------------
  test: lambda do |connection|
    get("zone/get_active_zones")
  end,

  # -------------------------------------------------------------------------
  # PICK LISTS BLOCK
  # Dynamically fetches zones and country codes from the user's Bright Data
  # account. Each product type has its own filtered zone list so users only
  # see relevant zones in each action's dropdown.
  # -------------------------------------------------------------------------
  pick_lists: {

    # Returns only Web Unlocker zones (type: "unblocker")
    unlocker_zones: lambda do |connection|
      get("zone/get_active_zones")
        .select { |zone| zone['type'] == 'unblocker' }
        .map { |zone| [zone['name'], zone['name']] }
    end,

    # Returns only SERP API zones (type: "serp")
    serp_zones: lambda do |connection|
      get("zone/get_active_zones")
        .select { |zone| zone['type'] == 'serp' }
        .map { |zone| [zone['name'], zone['name']] }
    end,

    # Returns all zones with their type shown in the label — useful for debugging
    all_zones: lambda do |connection|
      get("zone/get_active_zones")
        .map { |zone| ["#{zone['name']} (#{zone['type']})", zone['name']] }
    end,

    # Returns only Scraping Browser zones (type: "browser_api")
    browser_api_zones: lambda do |connection|
      get("zone/get_active_zones")
        .select { |zone| zone['type'] == 'browser_api' }
        .map { |zone| [zone['name'], zone['name']] }
    end,

    # Returns available country codes from GET /countrieslist.
    # ISP_shared is used as the reference zone type — it represents the
    # standard proxy pool used by Unlocker API and SERP API routing.
    country_codes: lambda do |connection|
      response = get("countrieslist")
      codes = response.dig('zone_type', 'ISP_shared', 'country_codes') || []
      codes
        .sort
        .map { |code| [code.upcase, code] }
    end

  },

  # -------------------------------------------------------------------------
  # ACTIONS BLOCK
  # -------------------------------------------------------------------------
  actions: {

    # =========================================================================
    # ACTION 1 — UNLOCKER API
    # Sends a POST /request to the Bright Data Unlocker API.
    # Bypasses anti-bot protections, manages proxies, and solves CAPTCHAs.
    # Supports both synchronous (immediate response) and asynchronous
    # (returns a response_id to poll later) modes.
    # =========================================================================
    unlocker_api_request: {
      title: "Unlocker API",
      subtitle: "Bright Data Unlocker API enables you to bypass anti-bot measures, " \
                "manages proxies, and solves CAPTCHAs automatically for easier web data collection.",

      description: lambda do |input, _picklist_label|
        url = input['url']
        if url.present?
          "Unlock <span class='provider'>#{url}</span> using <span class='provider'>Bright Data</span>"
        else
          "<span class='provider'>Unlock Website</span> using <span class='provider'>Bright Data</span>"
        end
      end,

      help: {
        body: "Unlock any website by bypassing anti-bot measures, CAPTCHAs, and IP blocks. " \
              "Use <b>format</b> to choose between raw HTML or structured JSON response. " \
              "Use <b>data_format</b> for markdown or screenshot output. " \
              "When using <b>Asynchronous</b> mode, the action returns a <b>Response ID</b> " \
              "instead of content — use it to poll for results later.",
        learn_more_url: "https://docs.brightdata.com/scraping-automation/web-unlocker/introduction",
        learn_more_text: "Learn more"
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: "async",
            label: "Request Mode",
            optional: true,
            type: "string",
            control_type: "select",
            options: [["Synchronous (default)", "false"], ["Asynchronous", "true"]],
            default: "false",
            hint: "Synchronous returns content immediately. Asynchronous returns a Response ID " \
                  "to poll later — recommended for high-volume requests. " \
                  "Requires async to be enabled on your zone in the Bright Data control panel."
          },
          {
            name: "zone",
            label: "Zone",
            optional: false,
            control_type: "select",
            pick_list: "unlocker_zones",
            toggle_hint: "Select from list",
            toggle_field: {
              name: "zone",
              label: "Zone ID",
              type: "string",
              control_type: "text",
              optional: false,
              toggle_hint: "Enter custom value",
              hint: "Enter your Web Unlocker zone identifier manually."
            },
            hint: "Select your Web Unlocker zone. Zones are fetched from your Bright Data account."
          },
          {
            name: "url",
            label: "Target URL",
            optional: false,
            hint: "Complete URL of the page to unlock. Must include protocol. " \
                  "Example: \"https://example.com/page\""
          },
          {
            name: "format",
            label: "Response Format",
            optional: false,
            control_type: "select",
            options: [["Raw (HTML)", "raw"], ["JSON", "json"]],
            default: "raw",
            hint: "'Raw' returns the HTML content as a string. 'JSON' returns structured data."
          },
          {
            name: "method",
            label: "Method",
            optional: true,
            control_type: "select",
            options: [["GET", "GET"], ["POST", "POST"]],
            default: "GET",
            hint: "HTTP method used when Bright Data requests the TARGET website. " \
                  "GET is the default for fetching pages. " \
                  "This is NOT the method of the Bright Data API call itself."
          },
          {
            name: "country",
            label: "Country",
            optional: true,
            control_type: "select",
            pick_list: "country_codes",
            toggle_hint: "Select from list",
            toggle_field: {
              name: "country",
              label: "Country Code",
              type: "string",
              control_type: "text",
              optional: true,
              toggle_hint: "Enter custom value",
              hint: "Two-letter ISO 3166-1 country code (e.g. 'us', 'gb', 'de'). " \
                    "<a href=\"https://docs.brightdata.com/general/faqs#where-can-i-see-the-list-of-country-codes\">Full list</a>."
            },
            hint: "Select the country for proxy geo-targeting. " \
                  "If omitted, Bright Data auto-selects the optimal location."
          },
          {
            name: "data_format",
            label: "Data Format",
            optional: true,
            control_type: "select",
            options: [["None", ""], ["Markdown", "markdown"], ["Screenshot", "screenshot"]],
            hint: "'Markdown' converts HTML to clean markdown (great for LLMs). " \
                  "'Screenshot' returns a PNG image of the rendered page."
          }
        ]
      end,

      execute: lambda do |connection, input|
        full_path = input['async'] == 'true' ? "request?async=true" : "request"

        payload = {
          zone:        input['zone'],
          url:         input['url'],
          format:      input['format'],
          method:      input['method'].presence,
          country:     input['country'].presence,
          data_format: input['data_format'].presence
        }.compact

        post(full_path, payload)
          .request_format_json
          .response_format_raw
          .after_response do |code, body, headers|
            {
              status_code:     code,
              content_type:    headers['content-type'],
              body:            body,
              brd_status_code: headers['x-brd-status-code'],
              response_id:     headers['x-response-id']
            }
          end
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "status_code",
            label: "HTTP Status Code",
            type: "integer",
            hint: "200 = success, 202 = async job accepted."
          },
          {
            name: "brd_status_code",
            label: "Bright Data Status Code",
            type: "string",
            hint: "The actual HTTP status code returned by the target website."
          },
          {
            name: "content_type",
            label: "Content Type",
            type: "string",
            hint: "Content type of the response (e.g., text/html, application/json)."
          },
          {
            name: "body",
            label: "Response Body",
            type: "string",
            hint: "The unlocked page content (HTML, Markdown, JSON, or empty if async)."
          },
          {
            name: "response_id",
            label: "Response ID (Async)",
            type: "string",
            hint: "Only populated when async=true. " \
                  "Poll GET /response?response_id=... to retrieve result. Stored 48 hours."
          }
        ]
      end
    },

  # =========================================================================
# ACTION 2 — SERP API
# Sends a POST /request to the Bright Data SERP API.
# Constructs the correct search engine URL based on the selected engine
# and user query, then returns structured or raw SERP results.
# Parsed JSON (brd_json=1) is only supported for Google and Bing.
# =========================================================================
    serp_api_request: {
  title: "SERP API",
  subtitle: "Extract search engine results using Bright Data SERP API. Get structured data " \
            "from Google, Bing, Yandex, DuckDuckGo, Yahoo, Baidu, Naver, and more.",

  description: lambda do |input, _picklist_label|
    engine = input['engine']
    query  = input['query']
    if engine.present? && query.present?
      "Scrape <span class='provider'>#{engine.capitalize}</span> for \"#{query}\" using <span class='provider'>Bright Data</span>"
    elsif engine.present?
      "Scrape <span class='provider'>#{engine.capitalize}</span> using <span class='provider'>Bright Data</span>"
    else
      "<span class='provider'>Scrape SERP</span> using <span class='provider'>Bright Data</span>"
    end
  end,

  help: {
    body: "Collect search engine results from Google, Bing, Yandex, DuckDuckGo, Yahoo, Baidu, and Naver. " \
          "Get organic results, ads, shopping results, local packs, and other SERP features. " \
          "Use <b>JSON</b> format for structured parsed output (Google & Bing only). " \
          "Use <b>Parsed Light</b> data format for faster top-10-only results.",
    learn_more_url: "https://docs.brightdata.com/scraping-automation/serp-api/introduction",
    learn_more_text: "Learn more"
  },

  input_fields: lambda do |object_definitions|
    [
      {
        name: "async",
        label: "Request Mode",
        optional: true,
        type: "string",
        control_type: "select",
        options: [["Synchronous", "false"], ["Asynchronous", "true"]],
        default: "false",
        hint: "Synchronous returns results immediately. Asynchronous returns a Response ID " \
              "to poll later — recommended for high-volume requests. " \
              "Requires async to be enabled on your zone in the Bright Data control panel."
      },
      {
        name: "zone",
        label: "Zone",
        optional: false,
        control_type: "select",
        pick_list: "serp_zones",
        toggle_hint: "Select from list",
        toggle_field: {
          name: "zone",
          label: "Zone ID",
          type: "string",
          control_type: "text",
          optional: false,
          toggle_hint: "Enter custom value",
          hint: "Enter your SERP API zone identifier manually."
        },
        hint: "Select your SERP API zone. Zones are fetched from your Bright Data account."
      },
      {
        name: "engine",
        label: "Search Engine",
        optional: false,
        control_type: "select",
        options: [
          ["Google",             "google"],
          ["Bing",               "bing"],
          ["Yandex",             "yandex"],
          ["DuckDuckGo",         "duckduckgo"],
          ["Yahoo",              "yahoo"],
          ["Baidu",              "baidu"],
          ["Naver",              "naver"],
          ["Other (Custom URL)", "other"]
        ],
        default: "google",
        toggle_hint: "Select from list",
        toggle_field: {
          name: "engine",
          label: "Search Engine",
          type: "string",
          control_type: "text",
          optional: false,
          toggle_hint: "Enter custom value",
          hint: "Enter a custom search engine identifier."
        },
        hint: "Select the search engine to query. " \
              "For unsupported engines use 'Other' and provide a full URL in the query field."
      },
      {
        name: "query",
        label: "Search Query",
        optional: false,
        sticky: true,
        hint: "Enter your search keyword (e.g. 'AI events in San Francisco'). " \
              "For 'Other', enter the full search URL. " \
              "Parsed JSON is only supported for Google and Bing. " \
              "For Baidu, queries in Chinese are supported and will be URL-encoded automatically."
      },
      {
        name: "format",
        label: "Response Format",
        optional: false,
        control_type: "select",
        options: [["Raw", "raw"], ["JSON", "json"]],
        default: "raw",
        hint: "'Raw' returns the HTML page source. " \
              "'JSON' returns structured parsed data — supported for Google and Bing only."
      },
      {
        name: "data_format",
        label: "Data Format",
        optional: true,
        control_type: "select",
        options: [["None", ""], ["Markdown", "markdown"], ["Screenshot", "screenshot"]],
        hint: "'Markdown' converts HTML to clean markdown. " \
              "'Screenshot' returns a PNG image of the rendered page."
      },
      {
        name: "country",
        label: "Country",
        optional: true,
        control_type: "select",
        pick_list: "country_codes",
        toggle_hint: "Select from list",
        toggle_field: {
          name: "country",
          label: "Country Code",
          type: "string",
          control_type: "text",
          optional: true,
          toggle_hint: "Enter custom value",
          hint: "Two-letter ISO 3166-1 country code (e.g. 'us', 'gb', 'de')."
        },
        hint: "Select the country for proxy geo-targeting. " \
              "If omitted, Bright Data auto-selects the optimal location."
      }
    ]
  end,

  execute: lambda do |connection, input|
    query_value   = input['query'].presence || ''
    encoded_query = URI.encode_www_form_component(query_value)
    brd_json      = input['format'] == 'json' ? "&brd_json=1" : ""

    target_url = case input['engine']
    when 'google'     then "https://www.google.com/search?q=#{encoded_query}#{brd_json}"
    when 'bing'       then "https://www.bing.com/search?q=#{encoded_query}#{brd_json}"
    when 'yandex'     then "https://www.yandex.com/search/?text=#{encoded_query}"
    when 'duckduckgo' then "https://duckduckgo.com/?q=#{encoded_query}"
    when 'yahoo'      then "https://search.yahoo.com/search?p=#{encoded_query}"
    when 'baidu'      then "https://www.baidu.com/s?wd=#{encoded_query}"
    when 'naver'      then "https://search.naver.com/search.naver?query=#{encoded_query}"
    when 'other'      then query_value
    else query_value
    end

    error("Please provide a search query or URL.") if target_url.blank?

    full_path = input['async'] == 'true' ? "request?async=true" : "request"

    payload = {
      zone:        input['zone'],
      url:         target_url,
      format:      input['format'],
      data_format: input['data_format'].presence,
      country:     input['country'].presence
    }.compact

    post(full_path, payload)
      .request_format_json
      .response_format_raw
      .after_response do |code, body, headers|
        parsed = body.is_a?(String) ? (JSON.parse(body) rescue body) : body

        serp_data = parsed
        if parsed.is_a?(Hash)
          inner = parsed['body']
          if inner.is_a?(String)
            serp_data = (JSON.parse(inner) rescue { 'raw_content' => inner })
          elsif inner.is_a?(Hash)
            serp_data = inner
          end
        end

        {
          status_code:   code,
          content_type:  headers['content-type'],
          request_url:   target_url,
          search_engine: input['engine'],
          response_id:   headers['x-response-id'],
          headers: {
            'content-type'              => headers['content-type'],
            'date'                      => headers['date'],
            'x-unblocker-redirected-to' => headers['x-unblocker-redirected-to'],
            'x-brd-warning'             => headers['x-brd-warning'],
            'x-luminati-error'          => headers['x-luminati-error'],
            'x-brd-error'               => headers['x-brd-error']
          },
          body: serp_data
        }
      end
  end,

  output_fields: lambda do |object_definitions|
    [
      { name: "status_code",   label: "HTTP Status Code",   type: "integer" },
      { name: "content_type",  label: "Content Type",       type: "string" },
      { name: "request_url",   label: "Request URL",        type: "string" },
      { name: "search_engine", label: "Search Engine Used", type: "string" },
      { name: "response_id",   label: "Response ID (Async)", type: "string",
        hint: "Only populated when async=true." },
      { name: "headers", label: "Response Headers", type: "object", properties: [
          { name: "content-type",              label: "Content Type" },
          { name: "date",                      label: "Date" },
          { name: "x-unblocker-redirected-to", label: "Redirected To URL" },
          { name: "x-brd-warning",             label: "Bright Data Warning" },
          { name: "x-luminati-error",          label: "Luminati Error" },
          { name: "x-brd-error",               label: "Bright Data Error" }
        ]
      },
      { name: "body", label: "Response Body", type: "object", properties: [
          { name: "raw_content", label: "Raw Content", type: "string",
            hint: "Populated only when the inner body could not be parsed as JSON." },
          { name: "general", type: "object", properties: [
              { name: "search_engine", label: "Search Engine" },
              { name: "query",         label: "Search Query" },
              { name: "results_cnt",   label: "Results Count",  type: "integer" },
              { name: "search_time",   label: "Search Time",    type: "number" },
              { name: "language",      label: "Language" },
              { name: "country",       label: "Country" },
              { name: "country_code",  label: "Country Code" },
              { name: "location",      label: "Location" },
              { name: "gl",            label: "GL (Geolocation)" },
              { name: "mobile",        label: "Is Mobile?",     type: "boolean" },
              { name: "basic_view",    label: "Basic View?",    type: "boolean" },
              { name: "search_type",   label: "Search Type" },
              { name: "page_title",    label: "SERP Page Title" },
              { name: "timestamp",     label: "Timestamp" }
            ]
          },
          { name: "input", type: "object", properties: [
              { name: "original_url", label: "Original Request URL" },
              { name: "request_id",   label: "Request ID" }
            ]
          },
          { name: "navigation", label: "Navigation", type: "array", of: "object", properties: [
              { name: "title", label: "Title" },
              { name: "href",  label: "Link" }
            ]
          },
          { name: "organic", label: "Organic Results", type: "array", of: "object", properties: [
              { name: "rank",         label: "Rank",        type: "integer" },
              { name: "global_rank",  label: "Global Rank", type: "integer" },
              { name: "title",        label: "Title" },
              { name: "description",  label: "Description" },
              { name: "link",         label: "URL" },
              { name: "display_link", label: "Display Link" },
              { name: "source",       label: "Source" },
              { name: "date",         label: "Date" },
              { name: "icon",         label: "Icon (Base64)" },
              { name: "snippet_highlighted_words", label: "Highlighted Words",
                type: "array", of: "string" },
              { name: "extensions", label: "Extensions", type: "array", of: "object", properties: [
                  { name: "type", label: "Type" },
                  { name: "text", label: "Text" },
                  { name: "link", label: "Link" },
                  { name: "rank", label: "Rank", type: "integer" }
                ]
              }
            ]
          },
          { name: "top_ads", label: "Top Ads", type: "array", of: "object", properties: [
              { name: "title",       label: "Ad Title" },
              { name: "link",        label: "Ad Link" },
              { name: "description", label: "Ad Description" }
            ]
          },
          { name: "bottom_ads", label: "Bottom Ads", type: "array", of: "object", properties: [
              { name: "title",       label: "Ad Title" },
              { name: "link",        label: "Ad Link" },
              { name: "description", label: "Ad Description" }
            ]
          },
          { name: "top_pla", label: "Product Listing Ads", type: "array", of: "object", properties: [
              { name: "title",         label: "Product Title" },
              { name: "price",         label: "Price" },
              { name: "shop",          label: "Shop Name" },
              { name: "image",         label: "Image URL" },
              { name: "referral_link", label: "Referral Link" }
            ]
          },
          { name: "local_pack", label: "Local Pack", type: "array", of: "object", properties: [
              { name: "title",   label: "Business Name" },
              { name: "address", label: "Address" },
              { name: "phone",   label: "Phone" },
              { name: "rating",  label: "Rating",       type: "number" },
              { name: "reviews", label: "Review Count", type: "integer" },
              { name: "link",    label: "Link" }
            ]
          },
          { name: "people_also_ask", label: "People Also Ask", type: "array", of: "object", properties: [
              { name: "question", label: "Question" },
              { name: "answer",   label: "Answer" },
              { name: "link",     label: "Source URL" },
              { name: "title",    label: "Source Title" }
            ]
          },
          { name: "related", label: "Related Searches", type: "array", of: "object", properties: [
              { name: "text",        label: "Search Term" },
              { name: "link",        label: "Search Link" },
              { name: "rank",        label: "Rank",        type: "integer" },
              { name: "global_rank", label: "Global Rank", type: "integer" }
            ]
          },
          { name: "pagination", type: "object", properties: [
              { name: "current_page",    label: "Current Page",    type: "integer" },
              { name: "next_page",       label: "Next Page",       type: "integer" },
              { name: "next_page_start", label: "Next Page Start", type: "integer" },
              { name: "next_page_link",  label: "Next Page URL" },
              { name: "pages", label: "Pages", type: "array", of: "object", properties: [
                  { name: "page",  label: "Page Number", type: "integer" },
                  { name: "start", label: "Start Index", type: "integer" },
                  { name: "link",  label: "Page Link" }
                ]
              }
            ]
          }
        ]
      }
    ]
  end
},

    # =========================================================================
    # ACTION 3 — MARKETPLACE DATASET API — Query Dataset (all GETs combined)
    # Uses object_definitions for dynamic fields and methods for shared logic.
    # =========================================================================
    query_dataset: {
      title: "Query Dataset",
      subtitle: "Retrieve Bright Data marketplace dataset information — " \
                "list datasets, inspect metadata, check snapshots, or download records.",

      description: lambda do |input, _picklist_label|
        labels = {
          'dataset_list'          => 'List Datasets',
          'get_dataset_metadata'  => 'Get Dataset Metadata',
          'get_snapshot_metadata' => 'Get Snapshot Metadata',
          'get_snapshot_parts'    => 'Get Snapshot Parts',
          'snapshot_content'      => 'Download Snapshot Content'
        }
        label = labels[input['action_type']] || 'Query Dataset'
        "<span class='provider'>#{label}</span> using <span class='provider'>Bright Data</span>"
      end,

      help: {
        body: "Query Bright Data marketplace datasets. Select an action type to: " \
              "<b>List</b> all available datasets, " \
              "<b>inspect metadata</b> for a specific dataset, " \
              "<b>check snapshot status</b>, " \
              "<b>get snapshot parts</b>, or " \
              "<b>download snapshot records</b>. " \
              "Recommended flow: Dataset List → Get Dataset Metadata → " \
              "Get Snapshot Metadata → Get Snapshot Parts → Snapshot Content.",
        learn_more_url: "https://docs.brightdata.com/api-reference/marketplace-dataset-api",
        learn_more_text: "Learn more"
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: "action_type",
            label: "Action Type",
            optional: false,
            control_type: "select",
            extends_schema: true,
            options: [
              ["Dataset List",          "dataset_list"],
              ["Get Dataset Metadata",  "get_dataset_metadata"],
              ["Get Snapshot Metadata", "get_snapshot_metadata"],
              ["Get Snapshot Parts",    "get_snapshot_parts"],
              ["Snapshot Content",      "snapshot_content"]
            ],
            hint: "Select what to retrieve. Fields will update based on your selection."
          }
        ] + object_definitions['dataset_query_fields']
      end,

      execute: lambda do |connection, input|
        path   = call('build_dataset_get_path', input)
        params = call('build_dataset_get_params', input)

        get(path)
          .params(params)
          .after_response do |code, body, headers|
            call('parse_dataset_get_response', input, code, body)
          end
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['dataset_query_output']
      end
    },

    # =========================================================================
    # ACTION 4 — MARKETPLACE DATASET API — Filter Dataset (POST)
    # =========================================================================
    filter_dataset: {
      title: "Filter Dataset",
      subtitle: "Filter a Bright Data marketplace dataset and create a snapshot " \
                "of matching records.",

      description: lambda do |input, _picklist_label|
        dataset_id = input['dataset_id']
        if dataset_id.present?
          "Filter dataset <span class='provider'>#{dataset_id}</span> " \
          "using <span class='provider'>Bright Data</span>"
        else
          "<span class='provider'>Filter Dataset</span> " \
          "using <span class='provider'>Bright Data</span>"
        end
      end,

      help: {
        body: "Filters a dataset and creates a snapshot of matching records. " \
              "Runs asynchronously (up to 5 min). Max filter nesting depth: 3." \
              "<br/><br/>" \
              "<b>Filter types:</b>" \
              "<br/>" \
              "• <b>Single field filter</b> — Field Name + Operator + Value. " \
              "Operators: <code>=</code>, <code>!=</code>, <code>&gt;</code>, <code>&gt;=</code>, " \
              "<code>&lt;</code>, <code>&lt;=</code>, <code>in</code>, <code>not_in</code>, " \
              "<code>includes</code>, <code>not_includes</code>, <code>array_includes</code>, " \
              "<code>not_array_includes</code>" \
              "<br/>" \
              "• <b>Filters group</b> — Combine multiple filters with <code>and</code> / <code>or</code>. " \
              "Optional: <code>combine_nested_fields</code> for arrays of objects." \
              "<br/>" \
              "• <b>Single field filter w/out value</b> — Null checks: " \
              "<code>is_null</code>, <code>is_not_null</code>" \
              "<br/><br/>" \
              "Returns <code>snapshot_id</code> — poll with <b>Query Dataset → Get Snapshot Metadata</b>, " \
              "then download with <b>Snapshot Content</b>.",
        learn_more_url: "https://docs.brightdata.com/api-reference/marketplace-dataset-api/filter-dataset",
        learn_more_text: "Bright Data Filter Dataset docs"
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: "dataset_id",
            label: "Dataset ID",
            optional: false,
            hint: "Unique identifier of the dataset to filter. " \
                  "Run <b>Query Dataset → Dataset List</b> to discover available IDs."
          },
          {
            name: "filter_type",
            label: "Filter Type",
            optional: false,
            control_type: "select",
            extends_schema: true,
            options: [
              ["Single field filter", "single_field"],
              ["Filters group", "filters_group"],
              ["Single field filter w/out value", "null_check"]
            ],
            hint: "Select the filter type. Fields and operators will update " \
                  "based on your selection."
          },
          {
            name: "records_limit",
            label: "Records Limit",
            optional: true,
            type: "integer",
            hint: "Maximum number of records to include in the snapshot. " \
                  "Useful for testing or cost control."
          }
        ] + object_definitions['filter_dataset_fields']
      end,

      execute: lambda do |connection, input|
        filter_type = input['filter_type']

        filter_obj = case filter_type
        when 'single_field'
          {
            name:     input['filter_name'],
            operator: input['filter_operator'],
            value:    input['filter_value']
          }
        when 'filters_group'
          parsed_filters = input['filter_group_json'].present? ?
            (JSON.parse(input['filter_group_json']) rescue []) : []
          obj = {
            operator: input['filter_group_operator'],
            filters:  parsed_filters
          }
          obj[:combine_nested_fields] = input['combine_nested_fields'] if input['combine_nested_fields']
          obj
        when 'null_check'
          {
            name:     input['filter_name'],
            operator: input['null_check_operator']
          }
        end

        payload = {
          dataset_id:    input['dataset_id'],
          filter:        filter_obj,
          records_limit: input['records_limit'].presence
        }.compact

        post("datasets/filter", payload)
          .request_format_json
          .after_response do |code, body, headers|
            parsed = JSON.parse(body) rescue {}
            {
              status_code:       code,
              snapshot_id:       parsed['snapshot_id'],
              error:             parsed['error'],
              validation_errors: parsed['validation_errors']
            }
          end
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "status_code",
            label: "HTTP Status Code",
            type: "integer",
            hint: "200 = started, 400 = bad filter, 402 = insufficient funds, " \
                  "422 = no records matched, 429 = too many jobs."
          },
          {
            name: "snapshot_id",
            label: "Snapshot ID",
            type: "string",
            hint: "Use in Query Dataset → Get Snapshot Metadata to poll status, " \
                  "then Query Dataset → Snapshot Content to download."
          },
          { name: "error",             label: "Error",             type: "string" },
          { name: "validation_errors", label: "Validation Errors", type: "array", of: "string" }
        ]
      end
    },

    # =========================================================================
    # ACTION 5 — MARKETPLACE DATASET API — Deliver Snapshot (POST)
    # =========================================================================
    deliver_snapshot: {
      title: "Deliver Snapshot",
      subtitle: "Push a Bright Data dataset snapshot to an external destination — " \
                "S3, GCS, Azure, Snowflake, Webhook, SFTP, and more.",

      description: lambda do |input, _picklist_label|
        snapshot_id   = input['snapshot_id']
        delivery_type = input['delivery_type']
        if snapshot_id.present? && delivery_type.present?
          "Deliver snapshot <span class='provider'>#{snapshot_id}</span> " \
          "to <span class='provider'>#{delivery_type.upcase}</span> " \
          "using <span class='provider'>Bright Data</span>"
        elsif snapshot_id.present?
          "Deliver snapshot <span class='provider'>#{snapshot_id}</span> " \
          "using <span class='provider'>Bright Data</span>"
        else
          "<span class='provider'>Deliver Snapshot</span> " \
          "using <span class='provider'>Bright Data</span>"
        end
      end,

      help: {
        body: "Pushes a ready snapshot to an external destination. " \
              "Supported: <b>Amazon S3</b>, <b>Google Cloud Storage</b>, " \
              "<b>Microsoft Azure</b>, <b>Snowflake</b>, <b>Webhook</b>, " \
              "<b>SFTP</b>, <b>GCS PubSub</b>, <b>Aliyun OSS</b>, " \
              "<b>Email</b>, <b>Build</b>. " \
              "Snapshot must have <b>status = ready</b> — " \
              "check with <b>Query Dataset → Get Snapshot Metadata</b> first.",
        learn_more_url: "https://docs.brightdata.com/api-reference/marketplace-dataset-api/deliver-snapshot",
        learn_more_text: "Learn more"
      },

      input_fields: lambda do |object_definitions|
        [
          {
            name: "snapshot_id",
            label: "Snapshot ID",
            optional: false,
            hint: "A <a href='https://docs.brightdata.com/api-reference/terminology#snapshot-id' target='_blank'>Snapshot ID</a> is a unique identifier for a specific data snapshot, used to retrieve results from a data collection job triggered via the API. " \
                  "Must have status = ready — check with Query Dataset → Get Snapshot Metadata."
          },
          {
            name: "delivery_type",
            label: "Delivery Type",
            optional: false,
            control_type: "select",
            extends_schema: true,
            options: [
              ["Microsoft Azure",              "azure"],
              ["Build",                        "build"],
              ["Email",                        "email"],
              ["Google Cloud Storage",         "gcs"],
              ["Google Cloud PubSub",          "gcs_pubsub"],
              ["Amazon S3",                    "s3"],
              ["SFTP",                         "sftp"],
              ["Snowflake",                    "snowflake"],
              ["Webhook",                      "webhook"],
              ["Aliyun Object Storage (OSS)",  "ali_oss"]
            ],
            hint: "Select the destination to deliver the snapshot to. " \
                  "Relevant fields will appear based on your selection."
          },
          {
            name: "filename_template",
            label: "Filename Template",
            optional: false,
            hint: "Template for the output filename (e.g. 'snapshot_{date}'). " \
                  "Placeholders like {date} are replaced automatically."
          },
          {
            name: "filename_extension",
            label: "File Extension",
            optional: false,
            control_type: "select",
            options: [["JSON", "json"], ["JSONL", "jsonl"], ["CSV", "csv"]],
            default: "json",
            hint: "Format of the delivered file."
          },
          {
            name: "compress",
            label: "Compress (gzip)",
            optional: true,
            control_type: "select",
            options: [["No", "false"], ["Yes", "true"]],
            default: "false",
            hint: "Deliver the file compressed in gzip format."
          },
          {
            name: "batch_size",
            label: "Batch Size",
            optional: true,
            type: "integer",
            hint: "Number of records per file. " \
                  "Recommended for snapshots with more than 1 million records."
          }
        ] + object_definitions['deliver_snapshot_fields']
      end,

      execute: lambda do |connection, input|
        delivery_type = input['delivery_type']

        filename = {
          template:  input['filename_template'],
          extension: input['filename_extension']
        }

        deliver_config = case delivery_type

        when 'azure'
          creds = { account: input['azure_account'] }
          creds[:sas_token] = input['azure_sas_token'] if input['azure_sas_token'].present?
          creds[:key]       = input['azure_key']       if input['azure_key'].present?
          {
            type:        'azure',
            filename:    filename,
            container:   input['azure_container'],
            directory:   input['azure_directory'].presence,
            credentials: creds
          }.compact

        when 'build'
          creds = {}
          creds[:account]   = input['build_account']   if input['build_account'].present?
          creds[:key]       = input['build_key']       if input['build_key'].present?
          creds[:sas_token] = input['build_sas_token']  if input['build_sas_token'].present?
          config = {
            type:        'build',
            filename:    filename,
            container:   input['build_container'].presence,
            directory:   input['build_directory'].presence,
            credentials: creds.present? ? creds : nil,
            endpoint:    input['build_endpoint'].presence
          }.compact
          config

        when 'email'
          creds = {}
          creds[:key]       = input['email_key']       if input['email_key'].present?
          creds[:sas_token] = input['email_sas_token']  if input['email_sas_token'].present?
          config = {
            type:        'email',
            filename:    filename,
            credentials: creds.present? ? creds : nil,
            endpoint:    input['email_endpoint'].presence
          }.compact
          config

        when 'gcs'
          gcs_creds = {
            client_email: input['gcs_client_email'],
            private_key:  input['gcs_private_key']
          }
          gcs_creds[:key] = input['gcs_key'] if input['gcs_key'].present?
          {
            type:        'gcs',
            filename:    filename,
            bucket:      input['gcs_bucket'],
            directory:   input['gcs_directory'].presence,
            credentials: gcs_creds
          }.compact

        when 'gcs_pubsub'
          config = {
            type:      'gcs_pubsub',
            filename:  filename,
            topic_id:  input['pubsub_topic_id'],
            container: input['pubsub_container'].presence,
            credentials: {
              client_email: input['pubsub_client_email'],
              private_key:  input['pubsub_private_key']
            }
          }.compact
          if input['pubsub_attributes'].present?
            config[:attributes] = JSON.parse(input['pubsub_attributes']) rescue []
          end
          config

        when 's3'
          s3_creds = {
            role_arn:    input['s3_role_arn'],
            external_id: input['s3_external_id']
          }
          s3_creds[:'aws-access-key'] = input['s3_access_key'] if input['s3_access_key'].present?
          s3_creds[:'aws-secret-key'] = input['s3_secret_key'] if input['s3_secret_key'].present?
          {
            type:         's3',
            filename:     filename,
            bucket:       input['s3_bucket'],
            region:       input['s3_region'].presence,
            directory:    input['s3_directory'].presence,
            endpoint_url: input['s3_endpoint_url'].presence,
            credentials:  s3_creds
          }.compact

        when 'sftp'
          creds = {
            username: input['sftp_username'],
            password: input['sftp_password']
          }
          creds[:ssh_key]    = input['sftp_ssh_key']    if input['sftp_ssh_key'].present?
          creds[:passphrase] = input['sftp_passphrase'] if input['sftp_passphrase'].present?
          {
            type:        'sftp',
            filename:    filename,
            path:        input['sftp_path'],
            port:        input['sftp_port'].presence,
            directory:   input['sftp_directory'].presence,
            credentials: creds
          }.compact

        when 'snowflake'
          sf_creds = {
            account:  input['snowflake_account'],
            user:     input['snowflake_user'],
            password: input['snowflake_password']
          }
          sf_creds[:key]       = input['snowflake_key']       if input['snowflake_key'].present?
          sf_creds[:sas_token] = input['snowflake_sas_token']  if input['snowflake_sas_token'].present?
          {
            type:        'snowflake',
            filename:    filename,
            database:    input['snowflake_database'],
            schema:      input['snowflake_schema'],
            stage:       input['snowflake_stage'],
            role:        input['snowflake_role'],
            warehouse:   input['snowflake_warehouse'],
            credentials: sf_creds
          }

        when 'webhook'
          wh_creds = {}
          wh_creds[:key]       = input['webhook_key']       if input['webhook_key'].present?
          wh_creds[:sas_token] = input['webhook_sas_token']  if input['webhook_sas_token'].present?
          config = {
            type:        'webhook',
            filename:    filename,
            endpoint:    input['webhook_endpoint'],
            credentials: wh_creds.present? ? wh_creds : nil
          }.compact
          config

        when 'ali_oss'
          ali_creds = {
            'access-key' => input['ali_access_key'],
            'secret-key' => input['ali_secret_key']
          }
          ali_creds['key']       = input['ali_key']       if input['ali_key'].present?
          ali_creds['sas_token'] = input['ali_sas_token']  if input['ali_sas_token'].present?
          {
            type:        'ali_oss',
            filename:    filename,
            bucket:      input['ali_bucket'],
            region:      input['ali_region'],
            directory:   input['ali_directory'].presence,
            credentials: ali_creds
          }.compact

        end

        payload = {
          deliver:    deliver_config,
          compress:   input['compress'] == 'true' ? true : nil,
          batch_size: input['batch_size'].presence
        }.compact

        post("datasets/snapshots/#{input['snapshot_id']}/deliver", payload)
          .request_format_json
          .after_response do |code, body, headers|
            parsed = body.is_a?(String) ? (JSON.parse(body) rescue {}) : (body.is_a?(Hash) ? body : {})
            {
              status_code: code,
              id:          parsed['id'],
              error:       parsed['error']
            }
          end
      end,

      output_fields: lambda do |object_definitions|
        [
          {
            name: "status_code",
            label: "HTTP Status Code",
            type: "integer",
            hint: "200 = delivery started, 404 = snapshot not found."
          },
          {
            name: "id",
            label: "ID",
            type: "string",
            hint: "Unique ID returned on success (200)."
          },
          {
            name: "error",
            label: "Error",
            type: "string",
            hint: "Error message returned on failure (e.g. 'Snapshot not found')."
          }
        ]
      end
    }

  },

  # -------------------------------------------------------------------------
  # TRIGGERS — empty for now
  # -------------------------------------------------------------------------
  triggers: {},

  # =========================================================================
  # OBJECT DEFINITIONS
  # Reusable field schemas — referenced by actions via object_definitions arg
  # =========================================================================
  object_definitions: {

    # -------------------------------------------------------------------------
    # Marketplace Dataset API — dynamic input fields per action type
    # -------------------------------------------------------------------------
    dataset_query_fields: {
      fields: lambda do |connection, config_fields|
        case config_fields['action_type']
        when 'dataset_list'
          []
        when 'get_dataset_metadata'
          [
            {
              name: "dataset_id",
              label: "Dataset ID",
              optional: false,
              hint: "Run Query Dataset → Dataset List to discover available IDs."
            }
          ]
        when 'get_snapshot_metadata'
          [
            {
              name: "snapshot_id",
              label: "Snapshot ID",
              optional: false,
              hint: "A <a href='https://docs.brightdata.com/api-reference/terminology#snapshot-id' target='_blank'>Snapshot ID</a> is a unique identifier for a specific data snapshot, used to retrieve results from a data collection job triggered via the API. " \
                    "Returned by Filter Dataset when a snapshot is triggered."
            }
          ]
        when 'get_snapshot_parts'
          [
            {
              name: "snapshot_id",
              label: "Snapshot ID",
              optional: false,
              hint: "A <a href='https://docs.brightdata.com/api-reference/terminology#snapshot-id' target='_blank'>Snapshot ID</a> is a unique identifier for a specific data snapshot. " \
                    "Must have status = ready."
            },
            {
              name: "format",
              label: "Format",
              optional: true,
              control_type: "select",
              options: [["JSON","json"],["NDJSON","ndjson"],["JSONL","jsonl"],["CSV","csv"]],
              default: "json",
              hint: "Must match the format used in Snapshot Content action."
            },
            {
              name: "compress",
              label: "Compressed (gzip)",
              optional: true,
              control_type: "select",
              options: [["No","false"],["Yes","true"]],
              default: "false",
              hint: "Must match Snapshot Content compress setting."
            },
            {
              name: "batch_size",
              label: "Batch Size",
              optional: true,
              type: "integer",
              hint: "Minimum 1000. Must match Snapshot Content action."
            }
          ]
        when 'snapshot_content'
          [
            {
              name: "snapshot_id",
              label: "Snapshot ID",
              optional: false,
              hint: "A <a href='https://docs.brightdata.com/api-reference/terminology#snapshot-id' target='_blank'>Snapshot ID</a> is a unique identifier for a specific data snapshot. " \
                    "Must have status = ready."
            },
            {
              name: "format",
              label: "Format",
              optional: true,
              control_type: "select",
              options: [["JSON","json"],["JSONL","jsonl"],["CSV","csv"]],
              default: "json",
              hint: "Must match Get Snapshot Parts format."
            },
            {
              name: "compress",
              label: "Compressed (gzip)",
              optional: true,
              control_type: "select",
              options: [["No","false"],["Yes","true"]],
              default: "false",
              hint: "Must match Get Snapshot Parts compress setting."
            },
            {
              name: "batch_size",
              label: "Batch Size",
              optional: true,
              type: "integer",
              hint: "Minimum 1000. Must match Get Snapshot Parts batch_size."
            },
            {
              name: "part",
              label: "Part Number",
              optional: true,
              type: "integer",
              hint: "Starts at 1. Iterate up to total parts from Get Snapshot Parts."
            }
          ]
        else
          []
        end
      end
    },

    # -------------------------------------------------------------------------
    # Marketplace Dataset API — dynamic output fields per action type
    # -------------------------------------------------------------------------
    dataset_query_output: {
      fields: lambda do |connection, config_fields|
        case config_fields['action_type']
        when 'dataset_list'
          [
            { name: "status_code", label: "HTTP Status Code", type: "integer" },
            { name: "datasets", label: "Datasets", type: "array", of: "object",
              properties: [
                { name: "id",   label: "Dataset ID",   type: "string" },
                { name: "name", label: "Dataset Name", type: "string" },
                { name: "size", label: "Record Count", type: "integer" }
              ]
            }
          ]
        when 'get_dataset_metadata'
          [
            { name: "status_code", label: "HTTP Status Code", type: "integer" },
            { name: "id",     label: "Dataset ID",     type: "string" },
            { name: "fields", label: "Dataset Fields", type: "object",
              hint: "Dynamic — one key per field. Each contains: type, active, required, description."
            }
          ]
        when 'get_snapshot_metadata'
          [
            { name: "status_code",     label: "HTTP Status Code",  type: "integer" },
            { name: "id",              label: "Snapshot ID",        type: "string" },
            { name: "created",         label: "Created At",         type: "string" },
            { name: "status",          label: "Status",             type: "string",
              hint: "scheduled / building / ready / failed."
            },
            { name: "dataset_id",      label: "Dataset ID",         type: "string" },
            { name: "customer_id",     label: "Customer ID",        type: "string" },
            { name: "dataset_size",    label: "Record Count",       type: "integer" },
            { name: "file_size",       label: "File Size (bytes)",  type: "integer" },
            { name: "cost",            label: "Cost",               type: "number" },
            { name: "error",           label: "Error",              type: "string" },
            { name: "error_code",      label: "Error Code",         type: "string" },
            { name: "warning",         label: "Warning",            type: "string" },
            { name: "warning_code",    label: "Warning Code",       type: "string" },
            { name: "initiation_type", label: "Initiation Type",    type: "string" }
          ]
        when 'get_snapshot_parts'
          [
            { name: "status_code", label: "HTTP Status Code", type: "integer" },
            { name: "parts",       label: "Total Parts",      type: "integer",
              hint: "Iterate from 1 to this number in Snapshot Content."
            }
          ]
        when 'snapshot_content'
          [
            { name: "status_code", label: "HTTP Status Code", type: "integer",
              hint: "200 = success, 202 = still building, 400 = bad request, 404 = not found."
            },
            { name: "snapshot_id", label: "Snapshot ID",  type: "string" },
            { name: "format",      label: "Format Used",  type: "string" },
            { name: "part",        label: "Part Number",  type: "integer" },
            { name: "records",     label: "Records",      type: "array", of: "object",
              hint: "Dynamic — field names vary per dataset. " \
                    "Use Get Dataset Metadata to discover available fields."
            }
          ]
        else
          []
        end
      end
    },

    # -------------------------------------------------------------------------
    # Filter Dataset — dynamic fields per filter type
    # -------------------------------------------------------------------------
    filter_dataset_fields: {
      fields: lambda do |connection, config_fields|
        case config_fields['filter_type']
        when 'single_field'
          [
            {
              name: "filter_name",
              label: "Field Name",
              optional: false,
              hint: "Field name to filter by (e.g. 'name', 'rating', 'industries')."
            },
            {
              name: "filter_operator",
              label: "Operator",
              optional: false,
              control_type: "select",
              options: [
                ["= (Equal)",                     "="],
                ["!= (Not equal)",                "!="],
                ["> (Greater than)",              ">"],
                [">= (Greater than or equal)",    ">="],
                ["< (Less than)",                 "<"],
                ["<= (Less than or equal)",       "<="],
                ["in (Value in list)",            "in"],
                ["not_in (Value not in list)",    "not_in"],
                ["includes (Contains)",           "includes"],
                ["not_includes (Not contains)",   "not_includes"],
                ["array_includes (Array match)",  "array_includes"],
                ["not_array_includes (No match)", "not_array_includes"]
              ],
              hint: "Comparison operator for the field."
            },
            {
              name: "filter_value",
              label: "Value",
              optional: false,
              hint: "Value to filter by. For <code>in</code>/<code>not_in</code> operators, " \
                    "provide a JSON array (e.g. [\"val1\", \"val2\"])."
            }
          ]
        when 'filters_group'
          [
            {
              name: "filter_group_operator",
              label: "Group Operator",
              optional: false,
              control_type: "select",
              options: [
                ["and (Match all)", "and"],
                ["or (Match any)",  "or"]
              ],
              hint: "Logical operator to combine the filters."
            },
            {
              name: "filter_group_json",
              label: "Filters (JSON array)",
              optional: false,
              hint: "JSON array of filter objects. Max nesting depth: 3." \
                    "<br/>Example: <code>[{\"name\":\"name\",\"operator\":\"=\",\"value\":\"John\"}," \
                    "{\"name\":\"age\",\"operator\":\">\",\"value\":\"30\"}]</code>"
            },
            {
              name: "combine_nested_fields",
              label: "Combine Nested Fields",
              optional: true,
              type: "boolean",
              control_type: "checkbox",
              hint: "For arrays of objects — if true, all filters must match " \
                    "within the same object."
            }
          ]
        when 'null_check'
          [
            {
              name: "filter_name",
              label: "Field Name",
              optional: false,
              hint: "Field name to check for null (e.g. 'reviews_count')."
            },
            {
              name: "null_check_operator",
              label: "Operator",
              optional: false,
              control_type: "select",
              options: [
                ["is_null (Is empty)",         "is_null"],
                ["is_not_null (Is not empty)", "is_not_null"]
              ],
              hint: "Check if the field value is null or not null."
            }
          ]
        else
          []
        end
      end
    },

    # -------------------------------------------------------------------------
    # Deliver Snapshot — dynamic credential fields per delivery type
    # -------------------------------------------------------------------------
    deliver_snapshot_fields: {
      fields: lambda do |connection, config_fields|
        case config_fields['delivery_type']

        when 'azure'
          [
            { name: "azure_container",  label: "Container",   optional: false,
              hint: "[Azure] Blob Storage container name (lowercase alphanumeric + hyphens)."
            },
            { name: "azure_directory",  label: "Directory",   optional: true,
              hint: "[Azure] Target folder path within the container."
            },
            { name: "azure_account",    label: "Account",    optional: false,
              hint: "[Azure] Storage account name."
            },
            { name: "azure_sas_token",  label: "SAS Token",   optional: true,
              control_type: "password",
              hint: "[Azure] Shared Access Signature token. Use either SAS Token or Access Key."
            },
            { name: "azure_key",        label: "Access Key",  optional: false,
              control_type: "password",
              hint: "[Azure] Storage account access key (required)."
            }
          ]

        when 'build'
          [
            { name: "build_container",  label: "Container",    optional: true,
              hint: "[Build] Container name."
            },
            { name: "build_directory",  label: "Directory",    optional: true,
              hint: "[Build] Target folder path within the container."
            },
            { name: "build_account",    label: "Account",     optional: true,
              hint: "[Build] Storage account name."
            },
            { name: "build_key",        label: "Access Key",   optional: false,
              control_type: "password",
              hint: "[Build] Storage account access key (required)."
            },
            { name: "build_sas_token",  label: "SAS Token",    optional: true,
              control_type: "password",
              hint: "[Build] Shared Access Signature token."
            },
            { name: "build_endpoint",   label: "Endpoint URL", optional: true,
              hint: "[Build] Endpoint URL for Bright Data Build delivery."
            }
          ]

        when 'email'
          [
            { name: "email_key",       label: "Access Key",   optional: true,
              control_type: "password",
              hint: "[Email] Access key for authentication."
            },
            { name: "email_sas_token", label: "SAS Token",    optional: true,
              control_type: "password",
              hint: "[Email] Shared Access Signature token."
            },
            { name: "email_endpoint",  label: "Endpoint URL", optional: true,
              hint: "[Email] Endpoint URL for email delivery."
            }
          ]

        when 'gcs'
          [
            { name: "gcs_bucket",       label: "Bucket",       optional: false,
              hint: "[GCS] Name of the Google Cloud Storage bucket."
            },
            { name: "gcs_directory",    label: "Directory",    optional: true,
              hint: "[GCS] Target folder path within the bucket."
            },
            { name: "gcs_client_email", label: "Client Email", optional: false,
              hint: "[GCS] Service account email (e.g. sa@project.iam.gserviceaccount.com)."
            },
            { name: "gcs_private_key",  label: "Private Key",  optional: false,
              control_type: "password",
              hint: "[GCS] Service account private key in PEM format."
            },
            { name: "gcs_key",          label: "Access Key",   optional: true,
              control_type: "password",
              hint: "[GCS] Optional access key for authentication."
            }
          ]

        when 'gcs_pubsub'
          [
            { name: "pubsub_topic_id",     label: "Topic ID",     optional: false,
              hint: "[GCS PubSub] Google Cloud PubSub topic ID."
            },
            { name: "pubsub_container",    label: "Container",    optional: true,
              hint: "[GCS PubSub] Container name."
            },
            { name: "pubsub_client_email", label: "Client Email", optional: false,
              hint: "[GCS PubSub] Service account email."
            },
            { name: "pubsub_private_key",  label: "Private Key",  optional: false,
              control_type: "password",
              hint: "[GCS PubSub] Service account private key in PEM format."
            },
            { name: "pubsub_attributes",   label: "Attributes (JSON)", optional: true,
              hint: "[GCS PubSub] Optional attributes as a JSON array string."
            }
          ]

        when 's3'
          [
            { name: "s3_bucket",       label: "Bucket",          optional: false,
              hint: "[S3] Name of the S3 bucket."
            },
            { name: "s3_role_arn",     label: "Role ARN",        optional: false,
              hint: "[S3] IAM Role ARN for role-based authentication (required)."
            },
            { name: "s3_external_id",  label: "External ID",     optional: false,
              hint: "[S3] External ID for Role ARN authentication (required)."
            },
            { name: "s3_access_key",   label: "AWS Access Key",  optional: true,
              control_type: "password",
              hint: "[S3] AWS access key ID."
            },
            { name: "s3_secret_key",   label: "AWS Secret Key",  optional: true,
              control_type: "password",
              hint: "[S3] AWS secret access key."
            },
            { name: "s3_endpoint_url", label: "Endpoint URL",    optional: true,
              hint: "[S3] Custom S3-compatible host URL. Only available with Access Key auth."
            },
            { name: "s3_region",       label: "Region",          optional: true,
              hint: "[S3] AWS region (e.g. 'us-east-1')."
            },
            { name: "s3_directory",    label: "Directory",       optional: true,
              hint: "[S3] Target folder path within the bucket."
            }
          ]

        when 'sftp'
          [
            { name: "sftp_path",       label: "Host",              optional: false,
              hint: "[SFTP] Hostname of the SFTP server."
            },
            { name: "sftp_port",       label: "Port",              optional: true,
              type: "integer",
              hint: "[SFTP] Port number (0-65535). Default is 22."
            },
            { name: "sftp_directory",  label: "Directory",         optional: true,
              hint: "[SFTP] Target directory path on the SFTP server."
            },
            { name: "sftp_username",   label: "Username",          optional: false,
              hint: "[SFTP] SFTP username."
            },
            { name: "sftp_password",   label: "Password",          optional: false,
              control_type: "password",
              hint: "[SFTP] SFTP password (required)."
            },
            { name: "sftp_ssh_key",    label: "SSH Key",           optional: true,
              control_type: "password",
              hint: "[SFTP] SSH private key (optional)."
            },
            { name: "sftp_passphrase", label: "SSH Key Passphrase", optional: true,
              control_type: "password",
              hint: "[SFTP] Passphrase for the SSH key if it is encrypted."
            }
          ]

        when 'snowflake'
          [
            { name: "snowflake_database",  label: "Database",  optional: false,
              hint: "[Snowflake] Target database name."
            },
            { name: "snowflake_schema",    label: "Schema",    optional: false,
              hint: "[Snowflake] Target schema name."
            },
            { name: "snowflake_stage",     label: "Stage",     optional: false,
              hint: "[Snowflake] Snowflake stage name."
            },
            { name: "snowflake_role",      label: "Role",      optional: false,
              hint: "[Snowflake] Snowflake role to use."
            },
            { name: "snowflake_warehouse", label: "Warehouse", optional: false,
              hint: "[Snowflake] Snowflake warehouse name."
            },
            { name: "snowflake_account",   label: "Account",   optional: false,
              hint: "[Snowflake] Snowflake account identifier."
            },
            { name: "snowflake_user",      label: "User",      optional: false,
              hint: "[Snowflake] Snowflake username."
            },
            { name: "snowflake_password",  label: "Password",  optional: false,
              control_type: "password",
              hint: "[Snowflake] Snowflake password."
            },
            { name: "snowflake_key",       label: "Access Key", optional: true,
              control_type: "password",
              hint: "[Snowflake] Optional access key for authentication."
            },
            { name: "snowflake_sas_token", label: "SAS Token",  optional: true,
              control_type: "password",
              hint: "[Snowflake] Optional SAS token for authentication."
            }
          ]

        when 'webhook'
          [
            { name: "webhook_endpoint",  label: "Endpoint URL",  optional: true,
              hint: "[Webhook] Full HTTPS URL to receive the snapshot payload."
            },
            { name: "webhook_key",       label: "Access Key",   optional: true,
              control_type: "password",
              hint: "[Webhook] Optional access key for authentication."
            },
            { name: "webhook_sas_token", label: "SAS Token",    optional: true,
              control_type: "password",
              hint: "[Webhook] Optional SAS token for authentication."
            }
          ]

        when 'ali_oss'
          [
            { name: "ali_bucket",     label: "Bucket",     optional: false,
              hint: "[Aliyun OSS] Name of the OSS bucket."
            },
            { name: "ali_region",     label: "Region",     optional: false,
              hint: "[Aliyun OSS] OSS region (e.g. 'oss-cn-hangzhou')."
            },
            { name: "ali_directory",  label: "Directory",  optional: true,
              hint: "[Aliyun OSS] Target folder path within the bucket."
            },
            { name: "ali_access_key", label: "Access Key", optional: false,
              control_type: "password",
              hint: "[Aliyun OSS] Aliyun access key ID."
            },
            { name: "ali_secret_key", label: "Secret Key", optional: false,
              control_type: "password",
              hint: "[Aliyun OSS] Aliyun secret access key."
            },
            { name: "ali_key",        label: "Access Key",  optional: true,
              control_type: "password",
              hint: "[Aliyun OSS] Optional access key."
            },
            { name: "ali_sas_token",  label: "SAS Token",  optional: true,
              control_type: "password",
              hint: "[Aliyun OSS] Optional SAS token for authentication."
            }
          ]

        else
          []
        end
      end
    }

  },

  # =========================================================================
  # METHODS
  # Reusable logic — called via call('method_name', args) from actions
  # =========================================================================
  methods: {

    # Builds the correct GET path based on action_type
    build_dataset_get_path: lambda do |input|
      case input['action_type']
      when 'dataset_list'          then "datasets/list"
      when 'get_dataset_metadata'  then "datasets/#{input['dataset_id']}/metadata"
      when 'get_snapshot_metadata' then "datasets/snapshots/#{input['snapshot_id']}"
      when 'get_snapshot_parts'    then "datasets/snapshots/#{input['snapshot_id']}/parts"
      when 'snapshot_content'      then "datasets/snapshots/#{input['snapshot_id']}/download"
      end
    end,

    # Builds query params for actions that need them
    build_dataset_get_params: lambda do |input|
      case input['action_type']
      when 'get_snapshot_parts', 'snapshot_content'
        {
          format:     input['format'].presence,
          compress:   input['compress'].presence,
          batch_size: input['batch_size'].presence,
          part:       input['action_type'] == 'snapshot_content' ? input['part'].presence : nil
        }.compact
      else
        {}
      end
    end,

    # Parses the response body per action type.
    # Workato's after_response may deliver `body` as already-parsed Ruby
    # object (Array/Hash) OR as a raw String, depending on Content-Type.
    # We handle both cases safely.
    parse_dataset_get_response: lambda do |input, code, body|
      parsed = body.is_a?(String) ? (JSON.parse(body) rescue body) : body

      case input['action_type']
      when 'dataset_list'
        datasets = parsed.is_a?(Array) ? parsed : []
        { status_code: code, datasets: datasets }

      when 'get_dataset_metadata'
        parsed = parsed.is_a?(Hash) ? parsed : {}
        { status_code: code, id: parsed['id'], fields: parsed['fields'] || {} }

      when 'get_snapshot_metadata'
        parsed = parsed.is_a?(Hash) ? parsed : {}
        {
          status_code:     code,
          id:              parsed['id'],
          created:         parsed['created'],
          status:          parsed['status'],
          dataset_id:      parsed['dataset_id'],
          customer_id:     parsed['customer_id'],
          dataset_size:    parsed['dataset_size'],
          file_size:       parsed['file_size'],
          cost:            parsed['cost'],
          error:           parsed['error'],
          error_code:      parsed['error_code'],
          warning:         parsed['warning'],
          warning_code:    parsed['warning_code'],
          initiation_type: parsed['initiation_type']
        }

      when 'get_snapshot_parts'
        parsed = parsed.is_a?(Hash) ? parsed : {}
        { status_code: code, parts: parsed['parts'] }

      when 'snapshot_content'
        records = parsed.is_a?(Array) ? parsed : [parsed]
        {
          status_code: code,
          snapshot_id: input['snapshot_id'],
          format:      input['format'],
          part:        input['part'],
          records:     records
        }
      end
    end

  }

}
