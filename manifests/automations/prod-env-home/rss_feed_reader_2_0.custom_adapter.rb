{
  title: 'RSS Feed Reader 2.0',

  methods: {
    parse_xml_to_hash: lambda do |xml_obj|
      xml_obj['xml']&.
      reject { |key, _value| key[/^@/] && !key[/@href/] }&.
        inject({}) do |hash, (key, value)|
        if value.is_a?(Array)
          hash.merge(if (array_fields = xml_obj['array_fields'])&.include?(key)
                       {
                         key => value.map do |inner_hash|
                                  call('parse_xml_to_hash',
                                       'xml' => inner_hash,
                                       'array_fields' => array_fields)
                                end
                       }
                     else
                       {
                         key => call('parse_xml_to_hash',
                                     'xml' => value[0],
                                     'array_fields' => array_fields)
                       }
                     end)
        else
          value
        end
      end&.presence
    end,

    format_api_output_field_names: lambda do |input|
      if input.is_a?(Array)
        input.map do |array_value|
          call('format_api_output_field_names',  array_value)
        end
      elsif input.is_a?(Hash)
        input.map do |key, value|
          value = call('format_api_output_field_names', value)
          { key.gsub(/[!@#$%^&*(),.?":{}|<>]/, '_') => value }
        end.inject(:merge)
      else
        input
      end
    end,

    format_schema_field_names: lambda do |input|
      input.map do |field|
        if field[:properties].present?
          field[:properties] = call('format_schema_field_names',
                                    field[:properties])
        elsif field['properties'].present?
          field['properties'] = call('format_schema_field_names',
                                     field['properties'])
        end
        if field[:name].present?
          field[:name] = field[:name].gsub(/[!@#$%^&*(),.?":{}|<>]/, '_')
        elsif field['name'].present?
          field['name'] = field['name'].gsub(/[!@#$%^&*(),.?":{}|<>]/, '_')
        end
        field
      end
    end
  },

  connection: { authorization: { type: 'no_auth' } },

  test: ->(_connection) { true },

  object_definitions: {
    item: {
      fields: lambda do |_connection, config_fields|
        custom_fields = if config_fields['custom_fields']
                          parse_json(config_fields['custom_fields'])
                        end

        item_fields = [
          { name: 'author' },
          { name: 'category' },
          { name: 'comments' },
          { name: 'description' },
          {
            type: 'object',
            name: 'enclosure',
            properties: [
              { name: '@length', label: 'Length' },
              { name: '@type', label: 'Type' },
              { name: '@url', label: 'URL' }
            ]
          },
          { name: 'guid', label: 'GUID' },
          { name: 'link' },
          {
            control_type: 'text',
            render_input: 'date_time_conversion',
            parse_output: 'date_time_conversion',
            type: 'date_time',
            name: 'pubDate'
          },
          { name: 'source' },
          { name: 'title' }
        ]

        schema = if custom_fields.present?
                   custom_fields
                 else
                   item_fields
                 end

        call('format_schema_field_names', schema.compact)
      end
    },

    channel: {
      fields: lambda do |_connection, config_fields|
        custom_fields = if config_fields['custom_fields']
                          parse_json(config_fields['custom_fields'])
                        end

        channel_fields = [
          { name: 'channel',
            type: 'object',
            properties: [
              { name: 'title' },
              { name: 'link' },
              { name: 'description' },
              { name: 'language' },
              { name: 'copyright' },
              { name: 'managingEditor' },
              {
                control_type: 'text',
                render_input: 'date_time_conversion',
                parse_output: 'date_time_conversion',
                type: 'date_time',
                name: 'pubDate'
              },
              {
                control_type: 'text',
                render_input: 'date_time_conversion',
                parse_output: 'date_time_conversion',
                type: 'date_time',
                name: 'lastBuildDate'
              },
              { name: 'category' },
              { name: 'generator' },
              { name: 'docs' },
              {
                type: 'object',
                name: 'cloud',
                properties: [
                  { name: '@domain', label: 'Domain' },
                  { name: '@path', label: 'Path' },
                  { name: '@url', label: 'URL' },
                  { name: '@port', label: 'Port' },
                  { name: '@protocol', label: 'Protocol' },
                  { name: '@registerProcedure', label: 'Register procedure' }
                ]
              },
              {
                control_type: 'text',
                label: 'Time to live',
                type: 'string',
                name: 'ttl'
              },
              {
                name: 'image',
                type: 'object',
                properties: [
                  { name: 'link' },
                  { name: 'title' },
                  { name: 'url' },
                  { name: 'description' },
                  { name: 'height' },
                  { name: 'width' }
                ]
              },
              { name: 'language' },
              { name: 'rating' },
              {
                type: 'object',
                name: 'textInput',
                properties: [
                  { name: 'description' },
                  { name: 'link' },
                  { name: 'name' },
                  { name: 'title' }
                ]
              },
              { name: 'webMaster' },
              {
                name: 'item',
                type: 'array',
                of: 'object',
                properties: [
                  { name: 'author' },
                  { name: 'category' },
                  { name: 'comments' },
                  { name: 'description' },
                  {
                    type: 'object',
                    name: 'enclosure',
                    properties: [
                      { name: '@length', label: 'Length' },
                      { name: '@type', label: 'Type' },
                      { name: '@url', label: 'URL' }
                    ]
                  },
                  { name: 'guid', label: 'GUID' },
                  { name: 'link' },
                  {
                    control_type: 'text',
                    render_input: 'date_time_conversion',
                    parse_output: 'date_time_conversion',
                    type: 'date_time',
                    name: 'pubDate'
                  },
                  { name: 'source' },
                  { name: 'title' }
                ]
              }
            ] }
        ]

        schema = if custom_fields.present?
                   custom_fields
                 else
                   channel_fields
                 end

        call('format_schema_field_names', schema.compact)
      end
    },

    new_item_input: {
      fields: lambda do |_connection, _config_fields, _object_definitions|
        [{
          name: 'feed_url',
          label: 'Feed URL',
          type: 'string',
          control_type: 'url',
          optional: false,
          hint: 'E.g. <b>https://status.workato.com/history.rss</b>'
        },
         {
           name: 'custom_fields',
           label: 'Custom feed schema',
           hint: 'Specify the output fields based on the feed\'s list array element.',
           sticky: true,
           extends_schema: true,
           schema_neutral: true,
           control_type: 'schema-designer',
           sample_data_type: 'json_input'
         },
         {
           name: 'feed_list_name',
           sticky: 'true',
           hint: 'Specify the list name to retrieve the items from. e.g. In this ' \
                 '<a href="https://status.workato.com/history.rss" target="_blank">feed</a>, ' \
                 'the list element containing the feed items is <<b>item</b>>. NOTE: This ' \
                 'is required if the array tag from the document is not <<b>item</b>>. If ' \
                 'not specified, it will not render as an array hence will trigger only ' \
                 '1 record.',
           control_type: 'text',
           extends_schema: true,
           type: 'string'
         }]
      end
    },
    get_feed_input: {
      fields: lambda do |_connection, config_fields, _object_definitions|
        [{
          name: 'feed_url',
          label: 'Feed URL',
          type: 'string',
          control_type: 'url',
          optional: false,
          hint: 'E.g. <b>https://status.workato.com/history.rss</b>'
        }, {
          name: 'custom_fields',
          label: 'Custom feed schema',
          control_type: 'schema-designer',
          hint: 'Specify the output fields based on the specified feed.',
          sticky: 'true',
          extends_schema: true,
          schema_neutral: true,
          sample_data_type: 'json_input'
        },
         (if config_fields['custom_fields'].present?
            {
              name: 'feed_list_name',
              sticky: 'true',
              hint: 'Specify the list name to retrieve the items from. e.g. In this ' \
                    '<a href="https://status.workato.com/history.rss" target="_blank">feed</a>, ' \
                    'the list element containing the feed items is <<b>item</b>>. NOTE: This ' \
                    'is required if the array tag from the document is not <<b>item</b>>. If not ' \
                    'specified, it will not render as an array in the output.',
              control_type: 'text',
              extends_schema: true,
              type: 'string'
            }
          end)].compact
      end
    }
  },

  actions: {
    get_feed: {
      description: "Get <span class='provider'>items</span> from feed in " \
        "<span class='provider'>RSS Feed Reader 2.0</span>",
      help: 'This action retrieves the details of an RSS feed in JSON format. To build a ' \
            'customized feed schema, provide the feed URL and run a test job. Then, copy the ' \
            'JSON data from the action output and paste it in the Custom feed schema builder.',

      input_fields: lambda do |object_definitions|
        object_definitions['get_feed_input']
      end,

      execute: lambda do |_connection, input|
        xml = get(input['feed_url']).response_format_xml
        xml = xml&.dig('feed', 0).presence || xml&.dig('rss', 0, 'channel', 0)
        item_fields = if input['array_name'].present?
                        [input['array_name']]
                      else
                        ['item']
                      end
        {
          channel: call('format_api_output_field_names',
                        call('parse_xml_to_hash',
                             'xml' => xml,
                             'array_fields' => item_fields)&.compact)
        }
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['channel']
      end,

      sample_output: lambda do |_connection, input|
        item_fields = if input['array_name'].present?
                        [input['array_name']]
                      else
                        ['item']
                      end

        {
          channel: [call('format_api_output_field_names',
                         call('parse_xml_to_hash',
                              'xml' => get(input['feed_url']).
                                       response_format_xml.
                                       dig('rss', 0, 'channel', 0),
                              'array_fields' => item_fields)&.compact)] || []
        }
      end
    }
  },

  triggers: {
    new_item_in_feed: {
      title: 'New feed item',
      subtitle: 'New feed item in RSS',
      description: "New <span class='provider'>item</span> in " \
        "<span class='provider'>RSS Feed Reader 2.0</span>",
      help: 'Checks for new events every 5 minutes. To build a customized feed schema, provide ' \
            'the feed URL and run a test job. Then, copy the JSON data from the action output ' \
            'and paste it in the Custom feed schema builder.',

      input_fields: lambda do |object_definitions|
        object_definitions['new_item_input']
      end,

      poll: lambda do |_connection, input, _page|
        xml = get(input['feed_url']).response_format_xml
        xml = xml&.dig('feed', 0).presence || xml&.dig('rss', 0, 'channel', 0)

        item_fields = if input['feed_list_name'].present?
                        input['feed_list_name']
                      else
                        'item'
                      end
        items = call('format_api_output_field_names',
                     call('parse_xml_to_hash',
                          'xml' => xml,
                          'array_fields' => [item_fields])&.compact&.[](item_fields))

        { events: items || [], next_page: nil }
      end,

      dedup: lambda do |item|
        item['id'] || item['guid'] || Time.now.to_f
      end,

      output_fields: ->(object_definitions) { object_definitions['item'] },

      sample_output: lambda do |_connection, input|
        call('format_api_output_field_names',
             call('parse_xml_to_hash',
                  'xml' => get(input['feed_url']).
                         response_format_xml.
                         dig('rss', 0, 'channel', 0),
                  'array_fields' => ['item'])&.dig('item', 0)) || {}
      end
    }
  }
}