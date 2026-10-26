{
  title: 'Monday.com',

  connection: {
    fields: [
      { name: 'api_key', label: 'API v2 Token',
        optional: false, control_type: 'password',
        hint: 'For admin users, login to Monday.com account > click on your ' \
              'avatar (picture icon) in the upper right corner of your screen ' \
              '> Go to Administration > API > Generate API v2 token. ' \
              "Click <a href='https://developer.monday.com/api-reference/docs/" \
              "authentication' target='_blank'>here</a> for more details." }
    ],

    authorization: {
      type: 'custom_auth',

      acquire: lambda do |_connection|
        {}
      end,
      apply: lambda do |connection|
        unless ['http://country.io/names.json'].include?(current_url)
          headers(Authorization: connection['api_key'], 'Api-version': '2024-10')
        end
      end
    },

    base_uri: lambda do |_connection|
      'https://api.monday.com/v2/'
    end
  },

  test: lambda do |_connection|
    response = post('', query: '{me{name}}').
               after_response do |_code, body, _headers|
                 if body['errors'].present?
                   error(body.dig('errors', 0, 'message'))
                 elsif body['error_code'].present? || body['error_message'].present?
                   error(body['error_message'])
                 else
                   body
                 end
               end
    response.after_error_response(/.*/) do |_code, body, _header, message|
      error("#{message}: #{body}")
    end
  end,

  object_definitions: {
    custom_operation_input: {
      fields: lambda do |connection, input|
        # collect problem messages here
        problems = []
        report_problem = lambda do |msg|
          problems << msg
        end

        # Custom query document
        query = input['query']
        unless query.blank?
          document = call(
            'parse_graphql',
            connection,
            report_problem,
            query
          )
          operations = document[:operations]
        end
        operations = [] if operations.nil?
        query_field = {
          name: 'query',
          label: 'GraphQL document',
          hint: 'Query fields will be matched against the application schema. ' \
                '<a href="https://graphql.org/learn/" target="_blank">Learn more</a>',
          multiline: true,
          control_type: 'code',
          optional: false,
          change_on_blur: true,
          extends_schema: true,
          schema_neutral: false,
          support_pills: true
        }
        fields = [
          query_field
        ]

        # Operation names
        operation_names = operations.map do |operation|
          operation[:operation_name]
        end&.compact
        # if there is more than 1 operation, always ask for the operation name
        if operations.length > 1
          operation_name_hint = 'Since the document contains multiple operations, ' \
                                'you must specify which one to perform.'
          if operation_names.length != operations.length
            operation_name_hint = "#{operation_name_hint} " \
                                  'In case you are missing an operation, ' \
                                  'you have to provide a operation name in the GraphQL document. ' \
                                  '<a href="https://graphql.org/learn/queries/#operation-name" ' \
                                  'target="_blank">Learn more</a>'
          end
          fields << {
            name: 'operation_name',
            label: 'Operation to perform',
            hint: operation_name_hint,
            control_type: :select,
            pick_list: operation_names.map do |name|
              [
                call('labelize', name),
                name
              ]
            end,
            extends_schema: true,
            schema_neutral: false,
            optional: false
          }
          operation_name = input['operation_name']
          if operation_name.present?
            operation = operations.find do |doc|
              doc[:operation_name] == operation_name
            end
          end
        else
          operation = operations.first
        end

        if operation.present?
          variable_fields = call(
            'create_custom_operation_variables_input_fields',
            connection,
            document,
            report_problem,
            operation
          )
          variable_fields&.each do |f|
            fields << f
          end
          call(
            'create_custom_operation_output_fields',
            connection,
            document,
            report_problem,
            operation
          )
        end
        if problems.present?
          hint = query_field[:hint]
          hint = "#{hint}<br>" unless hint.blank?
          query_field[:hint] = "#{hint}" \
                               '<b>Problems:</b><br>' \
                               "#{problems.join('<br>')}"
        end
        fields
      end
    },
    custom_operation_output: {
      fields: lambda do |connection, input|
        document = call(
          'parse_graphql',
          connection,
          nil,
          input['query']
        )
        operations = document&.[](:operations)
        if operations.present? && operations.length > 1
          operation_name = input['operation_name']
          operation = document&.[](:operations)&.find do |doc|
            doc[:operation_name] == operation_name
          end
        elsif operations.present? && operations.length == 1
          operation = operations.first
        end
        if operation.present?
          call(
            'create_custom_operation_output_fields',
            connection,
            document,
            nil,
            operation
          )
        else
          []
        end
      end
    },

    search_object_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        call('generate_schema', connection, config_fields, 'Query', 'input').
          concat(
            [
              {
                name: 'fields_to_retrieve',
                label: 'Select fields to retrieve',
                control_type: 'tree',
                sticky: true, extends_schema: true,
                pick_list: 'query_fields_list',
                pick_list_params: { recipe_api_version: 'recipe_api_version', object: 'object' },
                hint: 'Select all fields (including the nested object fields) ' \
                      'to be returned in the response.',
                tree_options: {
                  selectable_folder: true,
                  multi_select: true
                }
              }
            ]
          )
      end
    },
    search_object_output: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        call('generate_schema', connection, config_fields, 'Query', 'output')
      end
    },

    get_object_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        case call('get_recipe_api_version', config_fields)
        when '2023-07'
          if config_fields['object'] == 'items_by_column_values'
            call('format_get_items_page_by_column_values',
                 config_fields)
          end
        else
          error('Unhandled recipe API version')
        end
        if config_fields['object'] == 'items'
          [
            { name: 'id', label: 'Item ID',
              optional: false }
          ]
        else
          schema = call('generate_schema', connection, config_fields, 'Query', 'input')
          case call('get_recipe_api_version', config_fields)
          when '2023-07'
            schema = schema.
                     ignored('limit', 'columns').concat(
                       [
                         {
                           name: 'column_id', optional: false,
                           hint: "The column's unique identifier."
                         },
                         {
                           name: 'column_value', optional: false,
                           hint: 'The column value to search items by.'
                         },
                         {
                           name: 'limit', sticky: true,
                           type: 'interger', control_type: 'integer',
                           convert_input: 'integer_conversion',
                           default: 100,
                           hint: 'The maximum number of items to fetch in '\
                           'a single request. Use this to ' \
                                 'control the size of the result set and '\
                                 'manage pagination. Default: 100 and Maximum: 500.'
                         }
                       ]
                     )
          else
            error('Unhandled recipe API version')
          end
          schema
        end&.concat(
          [
            {
              name: 'fields_to_retrieve',
              label: 'Select fields to retrieve',
              control_type: 'tree',
              sticky: true, extends_schema: true,
              pick_list: 'query_fields_list',
              pick_list_params: { recipe_api_version: 'recipe_api_version', object: 'object' },
              hint: 'Select all fields (including the nested object fields) ' \
                    'to be returned in the response.',
              tree_options: {
                selectable_folder: true,
                multi_select: true
              }
            }
          ]
        )
      end
    },
    get_object_output: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        schema = call('generate_schema', connection, config_fields, 'Query', 'output')
        case call('get_recipe_api_version', config_fields)
        when '2023-07'
          if config_fields['object'] == 'items_by_column_values'
            call('format_get_items_page_by_column_values',
                 config_fields)
          end
          if config_fields['object'] == 'items_page_by_column_values'
            config_fields['object'] = 'items'
            schema = call('generate_schema', connection, config_fields, 'Query', 'output')
            config_fields['object'] = 'items_by_column_values'
            [
              { name: 'items_by_column_values', type: 'array', of: 'object',
                properties: schema.dig(0, :properties) }
            ]
          elsif config_fields['object'] == 'items'
            schema.dig(0, :properties)
          else
            schema
          end
        when 'default'
          # Default to run latest version of API.
          schema = call('generate_schema', connection, config_fields, 'Query', 'output')

          if config_fields['object'] == 'items'
            schema.dig(0, :properties)
          else
            schema
          end
        else
          error('Unhandled recipe API version')
        end
      end
    },

    create_object_input: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        fields = call('generate_schema', connection, config_fields, 'Mutation', 'input').
                 concat(
                   [
                     { name: 'fields_to_retrieve',
                       label: 'Select fields to retrieve',
                       control_type: 'tree',
                       sticky: true, extends_schema: true,
                       pick_list: 'mutate_fields_list',
                       pick_list_params: { recipe_api_version: 'recipe_api_version', object: 'object' },
                       hint: 'Select all fields (including the nested object fields) ' \
                             'to be returned in the response.',
                       tree_options: {
                         selectable_folder: true,
                         multi_select: true
                       } }
                   ]
                 )
        config_fields.each do |key, _value|
          next unless key.include?('_schema_builder')

          fields.concat([
                          { name: key.gsub('_schema_builder', ''), type: 'object',
                            properties: parse_json(config_fields[key]) }
                        ])
        end
        if %w[change_multiple_column_values create_item create_subitem].
           include?(config_fields['object'])
          hint = if config_fields['object'] == 'create_subitem'
                   'Select the <b>Board</b> of parent item ID'
                 end
          toggle_hint = if config_fields['object'] == 'create_subitem'
                          'Enter the <b>Board ID</b> of parent item ID.'
                        else
                          'Provide a valid Board ID. e.g. <b>123456</b>'
                        end
          fields = fields.ignored('column_values_schema_builder', 'column_values', 'board_id').
                   concat([
                            { name: 'board_id', label: 'Board name',
                              optional: false, sticky: true,
                              extends_schema: true,
                              control_type: 'select',
                              pick_list: 'board_list',
                              hint: hint,
                              toggle_hint: 'Select from list',
                              toggle_field: {
                                name: 'board_id', label: 'Board ID',
                                optional: false, sticky: true,
                                extends_schema: true, change_on_blur: true,
                                support_pills: false,
                                type: 'integer', control_type: 'integer',
                                convert_output: 'integer_conversion',
                                toggle_hint: 'Use custom value',
                                hint: toggle_hint
                              } },
                            { ngIf: 'false',
                              name: 'column_id', control_type: 'select',
                              pick_list: 'column_value_list',
                              pick_list_params: { board_id: 'board_id' } }
                          ])
          if config_fields['board_id'].present? &&
             (response = call('column_value_input_schema', config_fields)).present?
            fields.concat(
              [
                { name: 'column_values', type: 'object',
                  properties: response }
              ]
            )
          else
            fields
          end
        else
          fields
        end
      end
    },
    create_object_output: {
      fields: lambda do |connection, config_fields|
        next [] if config_fields.blank?

        call('generate_schema', connection, config_fields, 'Mutation', 'output')
      end
    },

    new_item_trigger_input: {
      fields: lambda do |_connection|
        [
          { name: 'since', type: :date_time,
            label: 'When first started, this recipe should pick up events from',
            optional: true,
            sticky: true,
            hint: 'When you start recipe for the first time, it picks up ' \
                  'records from this specified date and time. It process 1 ' \
                  'hour ago if left blank. Once recipe has ' \
                  'been run or tested, value cannot be changed.' },
          { name: 'board_id', label: 'Board name',
            optional: false, sticky: true,
            extends_schema: true,
            control_type: 'select',
            pick_list: 'board_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'board_id', label: 'Board ID',
              optional: false, sticky: true,
              extends_schema: true, change_on_blur: true,
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion',
              hint: 'Provide the valid Board ID. e.g. <b>123456</b>',
              toggle_hint: 'Use custom value'
            } }
        ]
      end
    },
    new_item_trigger_output: {
      fields: lambda do |_connection|
        [
          { name: 'id' },
          { name: 'created_at', type: 'date_time',
            control_type: 'date_time' },
          { name: 'event' },
          { name: 'entity' },
          { name: 'account_id' },
          { name: 'user_id' }
        ].concat(call('create_pulse_output_schema'))
      end
    },
    updated_column_value_trigger_input: {
      fields: lambda do |_connection|
        [
          { name: 'since', type: :date_time,
            label: 'When first started, this recipe should pick up events from',
            optional: true,
            sticky: true,
            hint: 'When you start recipe for the first time, it picks up ' \
                  'records from this specified date and time. It process 1 ' \
                  'hour ago if left blank. Once recipe has ' \
                  'been run or tested, value cannot be changed.' },
          { name: 'board_id', label: 'Board name',
            optional: false, sticky: true,
            extends_schema: true,
            control_type: 'select',
            pick_list: 'board_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'board_id', label: 'Board ID',
              optional: false, sticky: true,
              extends_schema: true, change_on_blur: true,
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion',
              hint: 'Provide the valid Board ID. e.g. <b>123456</b>',
              toggle_hint: 'Use custom value'
            } },
          { ngIf: 'input.board_id',
            name: 'column_id', label: 'Column name',
            optional: false, sticky: true,
            extends_schema: true,
            control_type: 'select',
            pick_list: 'column_list',
            pick_list_params: { board_id: 'board_id' },
            toggle_hint: 'Select from list',
            toggle_field: {
              ngIf: 'input.board_id',
              name: 'column_id', label: 'Column ID',
              optional: false, sticky: true,
              extends_schema: true, change_on_blur: true,
              type: 'string', control_type: 'text',
              toggle_hint: 'Use custom value'
            } }
        ]
      end
    },
    updated_column_value_trigger_output: {
      fields: lambda do |_connection, config_fields|
        [
          { name: 'id' },
          { name: 'created_at', type: 'date_time',
            control_type: 'date_time' },
          { name: 'event' },
          { name: 'entity' },
          { name: 'account_id' },
          { name: 'user_id' }
        ].concat(call('update_column_value_output_schema', config_fields))
      end
    },
    item_moved_trigger_input: {
      fields: lambda do |_connection|
        [
          { name: 'since', type: :date_time,
            label: 'When first started, this recipe should pick up events from',
            optional: true,
            sticky: true,
            hint: 'When you start recipe for the first time, it picks up ' \
                  'records from this specified date and time. It process 1 ' \
                  'hour ago if left blank. Once recipe has ' \
                  'been run or tested, value cannot be changed.' },
          { name: 'board_id', label: 'Board name',
            optional: false, sticky: true,
            extends_schema: true,
            control_type: 'select',
            pick_list: 'board_list',
            toggle_hint: 'Select from list',
            toggle_field: {
              name: 'board_id', label: 'Board ID',
              optional: false, sticky: true,
              extends_schema: true, change_on_blur: true,
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion',
              hint: 'Provide the valid Board ID. e.g. <b>123456</b>',
              toggle_hint: 'Use custom value'
            } },
          { ngIf: 'input.board_id',
            name: 'group_id', label: 'Group name',
            sticky: true, optional: false,
            control_type: 'select',
            pick_list: 'group_list',
            pick_list_params: { board_id: 'board_id' },
            toggle_hint: 'Select from list',
            toggle_field: {
              ngIf: 'input.board_id',
              name: 'group_id', label: 'Group ID',
              sticky: true, optional: false,
              type: 'string', control_type: 'text',
              toggle_hint: 'Use custom value'
            } }
        ]
      end
    },
    item_moved_trigger_output: {
      fields: lambda do |_connection|
        [
          { name: 'id' },
          { name: 'created_at', type: 'date_time',
            control_type: 'date_time' },
          { name: 'event' },
          { name: 'entity' },
          { name: 'account_id' },
          { name: 'user_id' }
        ].concat(call('move_pulse_into_group_output_schema'))
      end
    },

    board: {
      fields: lambda do
        [
          { name: 'id', type: 'integer', control_type: 'number' },
          { name: 'board_folder_id', type: 'integer', control_type: 'number' },
          { name: 'board_kind' },
          { name: 'columns', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' },
            { name: 'archived', type: 'boolean', control_type: 'checkbox' },
            { name: 'settings_str' },
            { name: 'title' },
            { name: 'type' },
            { name: 'width', type: 'integer', control_type: 'number' }
          ] },
          { name: 'description' },
          { name: 'groups', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' },
            { name: 'archived', type: 'boolean', control_type: 'checkbox' },
            { name: 'color' },
            { name: 'deleted', type: 'boolean', control_type: 'checkbox' },
            { name: 'items', type: 'array', of: 'object', properties: [
              { name: 'id', type: 'integer', control_type: 'number' }
            ] },
            { name: 'position' },
            { name: 'title' }
          ] },
          { name: 'items', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'name' },
          { name: 'owner', type: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'permissions' },
          { name: 'pos' },
          { name: 'state' },
          { name: 'subscribers', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'tags', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'updates', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] }
        ]
      end
    },
    column: {
      fields: lambda do
        [
          { name: 'id', type: 'integer', control_type: 'number' },
          { name: 'archived', type: 'boolean', control_type: 'checkbox' },
          { name: 'settings_str' },
          { name: 'title' },
          { name: 'type' },
          { name: 'width', type: 'integer', control_type: 'number' }
        ]
      end
    },
    item: {
      fields: lambda do |_, config_fields|
        next [] if config_fields.blank?

        board = post(
          'https://api.monday.com/v2',
          query: '{boards(ids: '\
                 "#{config_fields['board_id']})"\
                 '{columns{id,type,title,settings_str},groups{id,title}}}'
        )

        error("Unable to find a board with ID #{config_fields['board_id']}") unless board.present?
        unless board['data'].present?
          error("Unable to find a board with ID #{config_fields['board_id']}")
        end
        board = board['data']['boards'].first

        custom_fields = []
        board['columns'].each do |field|
          type = field['type']

          custom_fields << case type
                           when 'long-text'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'text' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'color'
                             { name: field['id'], label: field['title'],
                               type: 'object', properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'index' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'dropdown'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'ids', type: 'array', of: 'integer' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'multiple-person'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'personsAndTeams', type: 'array', of: 'object',
                                       properties: [
                                         { name: 'id', type: 'integer' },
                                         { name: 'kind' }
                                       ] },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'timezone'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'timezone' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'country'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'countryCode', label: 'Country Code' },
                                     { name: 'countryName', label: 'Country Name' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'email'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'email' },
                                     { name: 'text' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'phone'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'phone' },
                                     { name: 'countryShortName', label: 'Country Code' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'link'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'url' },
                                     { name: 'text' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'date'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'date' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'timerange'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'from' },
                                     { name: 'to' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'tag'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'tag_ids', type: 'array', of: 'integer' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'hour'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'hour' },
                                     { name: 'minute' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'week'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'week', type: 'object',
                                       properties: [
                                         { name: 'startDate', label: 'Start Date' },
                                         { name: 'endDate', label: 'End Date' }
                                       ] }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'boolean'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'checked' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'rating'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'rating', type: 'integer', control_type: 'number' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           when 'board-relation'
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value', type: 'object',
                                   properties: [
                                     { name: 'linkedPulseIds', type: 'array', of: 'object',
                                       properties: [
                                         { name: 'linkedPulseId', type: 'integer',
                                           control_type: 'number', label: 'Linked Item ID' }
                                       ], label: 'Linked Item IDs' },
                                     { name: 'changed_at' }
                                   ] },
                                 { name: 'type' }
                               ] }
                           else
                             { name: field['id'], label: field['title'],
                               type: 'object',
                               properties: [
                                 { name: 'id' },
                                 { name: 'text' },
                                 { name: 'title' },
                                 { name: 'value' },
                                 { name: 'type' }
                               ] }
                           end
        end
        [
          { name: 'id', type: 'integer', control_type: 'number' },
          { name: 'board', type: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'column_values', type: 'object', properties: custom_fields },
          { name: 'created_at' },
          { name: 'creator', type: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'creator_id' },
          { name: 'group', type: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' },
            { name: 'title' }
          ] },
          { name: 'name' },
          { name: 'state' },
          { name: 'subscribers', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'updated_at' },
          { name: 'updates', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] }
        ]
      end
    },
    update: {
      fields: lambda do
        [
          { name: 'body' },
          { name: 'created_at', type: 'date_time', control_type: 'date_time' },
          { name: 'creator_id' },
          { name: 'id' },
          { name: 'item_id' },
          { name: 'replies', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'text_body' },
          { name: 'updated_at', type: 'date_time', control_type: 'date_time' }
        ]
      end
    },
    tag: {
      fields: lambda do
        [
          { name: 'color' },
          { name: 'id', type: 'integer', control_type: 'number' },
          { name: 'name' }
        ]
      end
    },
    user: {
      fields: lambda do
        [
          { name: 'birthday', type: 'date_time', control_type: 'date_time' },
          { name: 'country_code' },
          { name: 'created_at', type: 'date_time', control_type: 'date_time' },
          { name: 'email' },
          { name: 'enabled', type: 'boolean', control_type: 'checkbox' },
          { name: 'id', type: 'integer', control_type: 'number' },
          { name: 'is_guest', type: 'boolean', control_type: 'checkbox' },
          { name: 'is_pending', type: 'boolean', control_type: 'checkbox' },
          { name: 'join_date', type: 'date_time', control_type: 'date_time' },
          { name: 'location' },
          { name: 'mobile_phone' },
          { name: 'name' },
          { name: 'phone' },
          { name: 'photo_original' },
          { name: 'photo_small' },
          { name: 'photo_thumbnail' },
          { name: 'photo_thumb_small' },
          { name: 'photo_tiny' },
          { name: 'teams', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] },
          { name: 'time_zone_identifier' },
          { name: 'title' },
          { name: 'url' },
          { name: 'utc_hours_diff', type: 'integer', control_type: 'number' }
        ]
      end
    },
    team: {
      fields: lambda do
        [
          { name: 'id', type: 'integer', control_type: 'number' },
          { name: 'name' },
          { name: 'picture_url' },
          { name: 'users', type: 'array', of: 'object', properties: [
            { name: 'id', type: 'integer', control_type: 'number' }
          ] }
        ]
      end
    },
    move_item_to_group: {
      fields: lambda do |_connection, config_fields|
        next [] if config_fields.blank?

        groups = post(
          'https://api.monday.com/v2',
          query: "{items(ids: #{config_fields['item_id']}){board{groups{id,title}}}}"
        )['data']['items'].first['board']['groups'].map { |group| [group['title'], group['id']] }

        group_id = { name: 'group_id', control_type: :select,
                     label: 'Group', optional: false,
                     pick_list: groups,
                     toggle_hint: 'Group',
                     toggle_field: {
                       name: 'group_id',
                       label: 'Group ID',
                       type: :string,
                       control_type: 'text',
                       optional: false,
                       toggle_hint: 'Use custom value'
                     } }
        ([group_id] || []).compact
      end
    },
    create_item: {
      fields: lambda do |_, config_fields|
        next [] if config_fields.blank?

        board = post(
          'https://api.monday.com/v2',
          query: "{boards(ids: #{config_fields['board_id']})"\
          '{columns{id,type,title,settings_str},groups{id,title}}}'
        )

        error("Unable to find a board with ID #{config_fields['board_id']}") unless board.present?
        unless board['data'].present?
          error("Unable to find a board with ID #{config_fields['board_id']}")
        end

        board = board['data']['boards'].first

        group_id = { name: 'group_id', control_type: :select,
                     label: 'Group', optional: false,
                     pick_list: board['groups']&.map { |group| [group['title'], group['id']] },
                     toggle_hint: 'Group',
                     toggle_field: {
                       name: 'group_id',
                       label: 'Group ID',
                       type: :string,
                       control_type: 'text',
                       optional: false,
                       toggle_hint: 'Use custom value'
                     } }

        custom_fields = board['columns'].map do |field|
          type = field['type']

          case type
          when 'long-text'
            { name: field['id'], type: 'object', properties: [
              { name: 'text', optional: true }
            ], label: field['title'], optional: true }
          when 'numeric'
            { name: field['id'], type: 'integer', control_type: 'number', label: field['title'],
              optional: true }
          when 'color'
            { name: field['id'], type: 'object', properties: [
              { name: 'label', control_type: :select, label: field['title'], optional: true,
                pick_list: parse_json(field['settings_str']&.to_s)['labels']&.map do |_k, v|
                             [v, v]
                           end,
                toggle_hint: field['title'], toggle_field: {
                  name: 'label',
                  label: 'Label',
                  type: :string,
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value'
                } }
            ], label: field['title'], optional: true }
          when 'dropdown'
            { name: field['id'], type: 'object', properties: [
              { name: 'labels', control_type: :multiselect,
                label: field['title'], optional: true,
                pick_list: parse_json(field['settings_str']&.to_s)['labels']&.map do |x|
                             [x['name'], x['name']]
                           end,
                toggle_hint: field['title'], toggle_field: {
                  name: 'labels',
                  label: 'Labels',
                  type: :string,
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value'
                } }
            ], label: field['title'], optional: true }
          when 'team'
            { name: field['id'], type: 'object', properties: [
              { name: 'team_id', type: 'integer', control_type: 'number', optional: true,
                parse_output: 'integer_conversion', render_input: 'integer_conversion' }
            ], label: field['title'], optional: true }
          when 'multiple-person'
            { name: field['id'], type: 'object', properties: [
              { name: 'personsAndTeams', type: 'array', of: 'object', label: field['title'],
                optional: true, properties: [
                  { name: 'id', type: 'integer', control_type: 'number', label: 'Person/Team ID',
                    optional: true,
                    parse_output: 'integer_conversion',
                    render_input: 'integer_conversion' },
                  { name: 'kind', label: 'Kind', control_type: :select, pick_list:
                    [
                      %w[Person person],
                      %w[Team team]
                    ],
                    optional: true, toggle_hint: 'kind',
                    toggle_field: {
                      name: 'kind',
                      label: 'Kind',
                      type: :string,
                      control_type: 'text',
                      optional: true,
                      toggle_hint: 'Use custom value'
                    } }
                ] }
            ], label: field['title'], optional: true }
          when 'timezone'
            { name: field['id'], type: 'object', properties: [
              { name: 'timezone', control_type: :select, label: field['title'], optional: true,
                pick_list: 'time_zone',
                toggle_hint: field['title'], toggle_field: {
                  name: 'timezone',
                  label: 'Time Zone',
                  type: :string,
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value'
                } }
            ], label: field['title'], optional: true }
          when 'country'
            { name: field['id'], type: 'object', properties: [
              { name: 'countryCode', control_type: :select, label: 'Country Code', optional: true,
                pick_list: 'country_codes',
                toggle_hint: field['title'], toggle_field: {
                  name: 'countryCode',
                  label: 'Country Code',
                  type: :string,
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value'
                } }
            ], label: field['title'], optional: true }
          when 'email'
            { name: field['id'], type: 'object', properties: [
              { name: 'email', optional: true },
              { name: 'text', optional: true }
            ], label: field['title'], optional: true }
          when 'phone'
            { name: field['id'], type: 'object', properties: [
              { name: 'phone', optional: true },
              { name: 'countryShortName', control_type: :select,
                label: 'Country Code', optional: true,
                pick_list: 'country_codes' }
            ], label: field['title'], optional: true }
          when 'link'
            { name: field['id'], type: 'object', properties: [
              { name: 'url', optional: true },
              { name: 'text', optional: true }
            ], label: field['title'], optional: true }
          when 'date'
            { name: field['id'], type: 'object', properties: [
              { name: 'date', type: 'date', control_type: 'date', optional: true },
              { name: 'time', type: 'time', control_type: 'time', optional: true }
            ], label: field['title'], optional: true }
          when 'timerange'
            { name: field['id'], type: 'object', properties: [
              { name: 'from', type: 'date', control_type: 'date', optional: true },
              { name: 'to', type: 'date', control_type: 'date', optional: true }
            ], label: field['title'], optional: true }
          when 'tag'
            tags = post(
              'https://api.monday.com/v2',
              query: '{tags{id,name}}'
            )['data']['tags'].map { |x| [x['name'], x['id'].to_i] }
            { name: field['id'], type: 'object', properties: [
              { name: 'tag_ids', control_type: :multiselect, label: field['title'], optional: true,
                pick_list: tags, toggle_hint: field['title'], toggle_field: {
                  name: 'tag_ids',
                  label: 'Tag IDs',
                  type: :string,
                  control_type: 'text',
                  optional: true,
                  toggle_hint: 'Use custom value'
                } }
            ], label: field['title'], optional: true }
          when 'hour'
            { name: field['id'], type: 'object', properties: [
              { name: 'hour', type: 'integer', control_type: 'number', optional: true,
                parse_output: 'integer_conversion', render_input: 'integer_conversion',
                hint: 'Hour should be in 24-hour format' },
              { name: 'minute', type: 'integer', control_type: 'number', optional: true,
                parse_output: 'integer_conversion', render_input: 'integer_conversion' }
            ], label: field['title'], optional: true }
          when 'week'
            { name: field['id'], type: 'object', properties: [
              { name: 'week', type: 'object', properties: [
                { name: 'startDate', type: 'date', control_type: 'date', optional: true },
                { name: 'endDate', type: 'date', control_type: 'date', optional: true }
              ], hint: 'Dates must be 7 days apart, inclusive, and start on Monday of ' \
                  'the given week.' }
            ], label: field['title'], optional: true }
          when 'boolean'
            { name: field['id'], type: 'object', properties: [
              { name: 'checked', type: 'boolean', control_type: 'checkbox' }
            ], label: field['title'], optional: true }
          when 'rating'
            { name: field['id'], type: 'object', properties: [
              { name: 'rating', type: 'integer', control_type: 'number', optional: true,
                parse_output: 'integer_conversion', render_input: 'integer_conversion' }
            ], label: field['title'], optional: true }
          when 'board-relation'
            { name: field['id'], type: 'object', properties: [
              { name: 'item_ids', type: :array, of: :number,
                parse_output: 'integer_conversion', render_input: 'integer_conversion' }
            ], label: field['title'], optional: true }
          else
            { name: field['id'], type: 'string', control_type: 'text', label: field['title'],
              optional: true }
          end
        end
        ([group_id].concat(custom_fields) || [])
      end
    },
    group: {
      fields: lambda do
        [
          { name: 'archived', type: 'boolean', control_type: 'checkbox' },
          { name: 'color' },
          { name: 'deleted', type: 'boolean', control_type: 'checkbox' },
          { name: 'id', type: 'integer', control_type: 'number' },
          { name: 'position' },
          { name: 'title' }
        ]
      end
    }
  },

  actions: {
    custom_operation: {
      title: 'Custom action',
      subtitle: 'Provide and run custom GraphQL query',
      help: {
        body: 'Use this action to run any custom GraphQL query.',
        learn_more_url: 'https://developer.monday.com/api-reference/docs',
        learn_more_text: 'Learn more'
      },
      description: lambda do |input, _picklist_label|
        operation_name = input['operation_name']
        if operation_name.blank?
          "Run <span class='provider'>" \
          'GraphQL query</span> in ' \
          "<span class='provider'>Monday.com</span>"
        else
          "Run <span class='provider'>" \
          "#{operation_name.labelize.downcase}</span> in " \
          "<span class='provider'>Monday.com</span>"
        end
      end,
      input_fields: lambda do |object_definitions|
        object_definitions['custom_operation_input']
      end,
      execute: lambda do |connection, input, eis, eos|
        call('execute_custom_operation', connection, input, eis, eos)
      end,
      output_fields: lambda do |object_definitions|
        object_definitions['custom_operation_output']
      end
    },
    search_records: {
      title: 'Search records',
      subtitle: 'Search records, e.g. users, in Monday.com',
      description: lambda do |_connection, search_object_list|
        "Search <span class='provider'>" \
        "#{search_object_list[:object]&.pluralize || 'records'}</span> " \
        'in <span class="provider">Monday.com</span>'
      end,

      help: 'Returns all records that matches your search criteria.',

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :search_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['search_object_input']
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end&.gsub(/items_page\s*{\s*items/, 'items_page (limit:500) { items')

        input = case call('get_recipe_api_version', input)
                when '2023-07'
                  if input['object'] == 'boards'
                    input.except('newest_first')
                  else
                    input
                  end
                else
                  error('Unhandled recipe API version')
                end
        params = call('format_input', input.except('recipe_api_version'), eis)
        params = params.present? ? "(#{params})" : ''
        payload = {
          query: "query {#{input['object']} #{params} #{call('format_output_fields', input,
                                                             output_fields)} }"
        }
        response = post('', payload).after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?                  
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
        end&.dig('data')
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['search_object_output']
      end,
      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },
    get_record: {
      title: 'Get record',
      subtitle: 'Get record, e.g. item, in Monday.com',
      description: lambda do |_connection, get_object_list|
        "Get <span class='provider'>" \
        "#{get_object_list[:object] || 'record'}</span> "\
        'in <span class="provider">Monday.com</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :get_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['get_object_input']
      end,

      execute: lambda do |_connection, input, eis, eos|
        if  call('get_recipe_api_version', input) == '2023-07'
          if input['object'] == 'items_by_column_values'
            call('format_get_items_page_by_column_values',
                 input)
          end
        else
          error('Unhandled recipe API version')
        end
        output_fields = if input['object'] == 'items_page_by_column_values' && input['fields_to_retrieve'].present?
                          "{ cursor items #{call('get_all_fields', input)} }"
                        elsif input['object'] == 'items_page_by_column_values'
                          "{ cursor items { #{call('get_root_fields', input['object'],
                                                   eos.dig(0, :properties)).join(' ')} } }"
                        elsif input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end
        if input['object'] == 'items'
          payload = {
            query: "query {#{input['object']} (ids: [#{input['id']}]) #{call(
              'format_output_fields', input, output_fields
            )} }"
          }
        else
          if input['object'] == 'items_page_by_column_values' && !input['limit'].present?
            input['limit'] = 100
          end

          if call('get_recipe_api_version', input) == '2023-07'
            input['columns'] = [{
              column_id: input.delete('column_id'),
              column_values: [input.delete('column_value')]
            }]
            if input['object'] == 'items_page_by_column_values'
              input = input.except('page', 'state', 'column_type')
            end
          else
            error('Unhandled recipe API version')
          end

          params = call('format_input', input.except('recipe_api_version'), eis)
          if call('get_recipe_api_version', input) == '2023-07'
            params = params.gsub('"column_id"', 'column_id').
                     gsub('"column_values"', 'column_values')
          else
            error('Unhandled recipe API version')
          end
          payload = {
            query: "query {#{input['object']} (#{params}) #{call('format_output_fields', input,
                                                                 output_fields)} }"
          }
        end
        response = post('', payload).
                   after_response do |_code, body, _headers|
                     if body['error_code'].present? || body['error_message'].present?
                       error(body['error_message'])
                     elsif body['errors'].present?
                       error(body.dig('errors', 0, 'message'))
                     else
                       body
                     end
                   end.after_error_response(/.*/) do |code, body, header, message|          
                    if code.to_i == 429 && header['retry_after'].present?
                      sleep(header['retry_after'].to_i + rand(1..30))
                      post('', payload).after_response do |code, body, headers|
                        if body['error_code'].present? || body['error_message'].present?
                          error(body['error_message'])
                        elsif body['errors'].present?
                          error(body.dig('errors', 0, 'message'))
                        else
                          body
                        end
                      end.after_error_response(/.*/) do |code, body, header, message|
                        if code.to_i == 429 && header['retry_after'].present?                  
                          sleep(header['retry_after'].to_i + rand(1..30))
                          post('', payload).after_response do |_code, body, _headers|
                            if body['error_code'].present? || body['error_message'].present?
                              error(body['error_message'])
                            elsif body['errors'].present?
                              error(body.dig('errors', 0, 'message'))
                            else
                              body
                            end
                          end
                        else
                          error("#{message}: #{body}")
                        end
                      end
                    else
                      error("#{message}: #{body}")
                    end
                  end&.dig('data')
                   
        if input['object'] == 'items'
          response = response&.dig('items', 0)
        elsif input['object'] == 'items_page_by_column_values'
          case call('get_recipe_api_version', input)
          when '2023-07'
            response = { 'items_by_column_values' => response&.dig('items_page_by_column_values', 'items'),
                         'cursor' => response&.dig('items_page_by_column_values', 'cursor') }
          else
            error('Unhandled recipe API version')
          end
        else
          response
        end
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['get_object_output']
      end,

      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },
    create_record: {
      title: 'Create record',
      subtitle: 'Create record, e.g. item, in Monday.com',
      description: lambda do |_connection, create_object_list|
        "Create <span class='provider'>" \
        "#{create_object_list[:object] || 'record'}</span> "\
        'in <span class="provider">Monday.com</span>'
      end,
      help: lambda do |_input, create_object_list|
        if create_object_list[:object] == 'Item'
          "Refer <a href='https://developer.monday.com/api-reference/docs/change-column-" \
          "values' target='_blank'>API documentation</a> for more detail on Column values."
        elsif create_object_list[:object] == 'Subitem'
          "Refer <a href='https://developer.monday.com/api-reference/docs/change-column-" \
          "values' target='_blank'>API documentation</a> for more detail on Column values. " \
          '<br><b>Note: To create subitems, there should be a subitem column on the board.</b>'
        end
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :create_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input']
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end
        params = if input['object'] == 'create_subitem'
                   call('format_input', input.except('board_id', 'recipe_api_version'), eis)
                 else
                   call('format_input', input.except('recipe_api_version'), eis)
                 end
        params = case call('get_recipe_api_version', input)
                 when '2023-07'
                   params&.gsub('tag_ids', 'ids')
                 else
                   error('Unhandled recipe API version')
                 end
        payload = {
          query: "mutation {#{input['object']} (#{params}) #{call('format_output_fields', input,
                                                                  output_fields)} }"
        }
        response = post('', payload).
                   after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|          
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?                  
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
        end&.dig('data', input['object'])
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,
      
      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },

    update_record: {
      title: 'Update record',
      subtitle: 'Update record, e.g. item, in Monday.com',
      description: lambda do |_connection, update_object_list|
        "Update <span class='provider'>" \
        "#{update_object_list[:object] || 'record'}</span> "\
        'by ID in <span class="provider">Monday.com</span>'
      end,
      help: lambda do |_input, update_object_list|
        if %w[Item].include?(update_object_list[:object])
          "Refer <a href='https://api.developer.monday.com/docs/change-column-" \
          "values' target='_blank'>API documentation</a> for more detail on Column values. <br>"\
          "Passing the null value or empty string('') will clear the column."\
          "Use the 'Clear column value' action to clear the value of each supported column."
        end
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :update_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        [
          { name: 'workato_clear_column',
            label: 'Clear column',
            type: 'boolean',
            control_type: 'checkbox',
            default: false, sticky: true,
            toggle_hint: 'Select from list',
            convert_input: 'boolean_conversion',
            hint: 'Select "Yes" to clear all the column values if the "null" '  \
                  'value or empty string ("") is passed. Or select "No" to ignore "null" value. ' \
                  'Default value is "No"',
            toggle_field: {
              name: 'workato_clear_column', label: 'Clear column',
              type: 'string', control_type: 'text',
              default: false,
              optional: true, sticky: true,
              convert_input: 'boolean_conversion',
              hint: 'Accepted values are true or false',
              toggle_hint: 'Use custom value',
              hint: 'Provide "true" to clear all the column values if the "null" '  \
                    'value or empty string ("") is passed. Or provide "false" to ignore "null" value. ' \
                    'Default value is "false"'
            } }
        ].concat(object_definitions['create_object_input'].required('item_id'))
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end

        params = call('format_input', input.except('recipe_api_version'), eis)
        # params = case call('get_recipe_api_version', input)
        #          when '2023-07'
        #            params&.gsub('tag_ids', 'ids')
        #          else
        #            error('Unhandled recipe API version')
        #          end
        params = params.gsub('workato_clear_column:false', '').gsub('workato_clear_column:true', '')
        payload = {
          query: "mutation {#{input['object']} (#{params}) #{call('format_output_fields', input,
                                                                  output_fields)} }"
        }
        response = post('', payload).
                   after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
        end&.dig('data', input['object'])
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,
      
      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },
    # Added and deprecated this update record action since we are unable to support backward compatibility to it.
    update_record_new: {
      deprecated: true,
      title: 'Update record',
      subtitle: 'Update record, e.g. item, in Monday.com',
      description: lambda do |_connection, update_object_list|
        "Update <span class='provider'>" \
        "#{update_object_list[:object] || 'record'}</span> "\
        'by ID in <span class="provider">Monday.com</span>'
      end,
      help: lambda do |_input, update_object_list|
        if %w[Item].include?(update_object_list[:object])
          "Refer <a href='https://developer.monday.com/api-reference/reference" \
          "/columns#change-multiple-column-values' target='_blank'>API " \
          'documentation</a> for more detail on Column values. <br>' \
        end
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :update_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-10'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input'].required('item_id')
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end

        params = call('format_input', input.except('recipe_api_version'), eis)
        payload = {
          query: "mutation {#{input['object']} (#{params}) #{output_fields} }"
        }
        response = post('', payload).
                   after_response do |_code, body, _headers|
                     if body['error_code'].present? || body['error_message'].present?
                       error(body['error_message'])
                     elsif body['errors'].present?
                       error(body.dig('errors', 0, 'message'))
                     else
                       body
                     end
                   end
        response.after_error_response(/.*/) do |_code, body, _header, message|
          error("#{message}: #{body}")
        end&.dig('data', input['object'])
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end
    },
    clear_column_value: {
      title: 'Clear column value',
      subtitle: 'Clear column value in Monday.com',
      description: lambda do |_connection, _update_object_list|
        "Clear <span class='provider'>" \
        ' column value</span> '\
        'in <span class="provider">Monday.com</span>'
      end,
      help: 'This action helps in clearing the specified '\
      'column value of the specified item. <br> Please ensure '\
      'that you review the supported and unsupported columns'\
      " to verify whether the column supports the 'clear column'"\
      ' action. To do this, go through each column in the'\
      " <a href='https://developer.monday.com/"\
        "api-reference/docs/column-types-reference' "\
        "target='_blank'>column types reference</a>.",
      config_fields: [
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],
      input_fields: lambda do |_object_definitions|
        [
          { name: 'board_id',
            optional: false,
            control_type: 'select',
            pick_list: 'board_list',
            toggle_hint: 'Board ID', toggle_field: {
              name: 'board_id',
              label: 'Board ID',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value'
            } },
          { name: 'column',
            optional: false,
            control_type: 'select',
            pick_list: 'column_list_with_type',
            pick_list_params: { board_id: 'board_id' },
            toggle_hint: 'Column', toggle_field: {
              name: 'column',
              label: 'Column',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value',
              hint: 'Allowed values are: column which supports '\
              "clear column value. <a href='https://developer.monday.com/"\
              "api-reference/docs/column-types-reference' "\
              "target='_blank'>Learn more</a>"
            } },
          { name: 'item_id', label: 'Item ID',
            optional: false,
            parse_output: 'integer_conversion',
            render_input: 'integer_conversion' }
        ]
      end,

      execute: lambda do |_connection, input|
        case input['column']
        when 'files', 'monday_doc'
          payload = {
            query: "mutation { change_column_value(item_id: #{input['item_id']},"\
            "board_id: #{input['board_id']}, "\
            "column_id: \"#{input['column']}\", "\
            'value: "{\\"clear_all\\" : true}"'\
            ' ) { id } }'
          }
        else
          payload = {
            query: "mutation { change_multiple_column_values(item_id: #{input['item_id']},"\
            "board_id: #{input['board_id']}, "\
            "column_values: \"{\\\"#{input['column']}\\\" : null}\""\
            ' ) { id } }'
          }
        end

        response = post('', payload).
                   after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
      end
      call('format_response', response, input)
    end,
    
    retry_on_response: [429],
    retry_on_request: %w[POST],
    max_retries: 3
    },
    upload_file: {
      title: 'Upload file',
      subtitle: 'Upload file in Monday.com',
      description: lambda do |_connection, update_object_list|
        "Upload <span class='provider'>" \
        "#{update_object_list[:object] || 'file'}</span> "\
        'in <span class="provider">Monday.com</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :upload_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input'].ignored('file').concat(
          [
            { name: 'file', label: 'File content',
              optional: false,
              hint: 'The file content to upload.' },
            { name: 'file_name', optional: false,
              hint: 'File name with extension. e.g. <b>image.jpg</b>' }
          ]
        )
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end
        params = call('format_input', input.except('file', 'file_name', 'recipe_api_version'), eis)
        payload = {
          "variables[file]": [input['file'], 'application/octet-stream', input['file_name']],
          query: "mutation ($file: File!) {#{input['object']} "\
          "(file: $file, #{params}) #{call('format_output_fields', input, output_fields)} }"
        }
        response = post('file', payload).request_format_multipart_form.
                   after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
        end&.dig('data', input['object'])
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,
      
      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },
    move_record: {
      title: 'Move record',
      subtitle: 'Move record, e.g. item, in Monday.com',
      description: lambda do |_connection, move_object_list|
        "Move <span class='provider'>" \
        "#{move_object_list[:object] || 'record'}</span> "\
        'in <span class="provider">Monday.com</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :move_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input'].required('item_id')
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end
        params = call('format_input', input.except('recipe_api_version'), eis)
        if input['object'] == 'move_item_to_board'
          params = params.gsub('"source":', 'source:').gsub('"target":', 'target:')
        end
        payload = {
          query: "mutation {#{input['object']} (#{params}) #{call('format_output_fields', input,
                                                                  output_fields)} }"
        }
        response = post('', payload).
                   after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
        end&.dig('data', input['object'])
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,
      
      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },
    archive_record: {
      title: 'Archive record',
      subtitle: 'Archive record, e.g. item, in Monday.com',
      description: lambda do |_connection, archive_object_list|
        "Archive <span class='provider'>" \
        "#{archive_object_list[:object] || 'record'}</span> "\
        'in <span class="provider">Monday.com</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :archive_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input'].required('item_id')
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end
        params = call('format_input', input.except('recipe_api_version'), eis)
        payload = {
          query: "mutation {#{input['object']} (#{params}) #{call('format_output_fields', input,
                                                                  output_fields)} }"
        }
        response = post('', payload).
                   after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
        end&.dig('data', input['object'])
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,
      
      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },
    delete_record: {
      title: 'Delete record',
      subtitle: 'Delete record, e.g. item, in Monday.com',
      description: lambda do |_connection, delete_object_list|
        "Delete <span class='provider'>" \
        "#{delete_object_list[:object] || 'record'}</span> "\
        'by ID in <span class="provider">Monday.com</span>'
      end,

      config_fields: [
        {
          name: 'object',
          optional: false,
          control_type: 'select',
          pick_list: :delete_object_list,
          hint: 'Select the object from list.'
        },
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['create_object_input']
      end,

      execute: lambda do |_connection, input, eis, eos|
        output_fields = if input['fields_to_retrieve'].present?
                          call('get_all_fields', input)
                        else
                          "{ #{call('get_root_fields', input['object'], eos).join(' ')} }"
                        end
        params = call('format_input', input.except('recipe_api_version'), eis)
        payload = {
          query: "mutation {#{input['object']} (#{params}) #{call('format_output_fields', input,
                                                                  output_fields)} }"
        }
        response = post('', payload).
                   after_response do |_code, body, _headers|
          if body['error_code'].present? || body['error_message'].present?
            error(body['error_message'])
          elsif body['errors'].present?
            error(body.dig('errors', 0, 'message'))
          else
            body
          end
        end.after_error_response(/.*/) do |code, body, header, message|
          if code.to_i == 429 && header['retry_after'].present?
            sleep(header['retry_after'].to_i + rand(1..30))
            post('', payload).after_response do |code, body, headers|
              if body['error_code'].present? || body['error_message'].present?
                error(body['error_message'])
              elsif body['errors'].present?
                error(body.dig('errors', 0, 'message'))
              else
                body
              end
            end.after_error_response(/.*/) do |code, body, header, message|
              if code.to_i == 429 && header['retry_after'].present?
                sleep(header['retry_after'].to_i + rand(1..30))
                post('', payload).after_response do |_code, body, _headers|
                  if body['error_code'].present? || body['error_message'].present?
                    error(body['error_message'])
                  elsif body['errors'].present?
                    error(body.dig('errors', 0, 'message'))
                  else
                    body
                  end
                end
              else
                error("#{message}: #{body}")
              end
            end
          else
            error("#{message}: #{body}")
          end
        end&.dig('data', input['object'])
        call('format_response', response, input)
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['create_object_output']
      end,
      
      retry_on_response: [429],
      retry_on_request: %w[POST],
      max_retries: 3
    },

    custom_query: {
      deprecated: true,
      description: 'Run a custom GraphQL query in ' \
        "<span class='provider'>Monday</span>",
      title: 'Custom Query',

      input_fields: lambda do |_object_definitions|
        [
          { name: 'query', optional: false }
        ]
      end,

      execute: lambda do |_connection, input|
        {
          item: post('https://api.monday.com/v2').payload(
            query: input['query']
          )
        }
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'item', type: 'object', properties: [
            { name: 'data' },
            { name: 'account_id', type: 'integer', control_type: 'number' }
          ] }
        ]
      end
    },
    get_item: {
      deprecated: true,
      description: "Retrieve a <span class='provider'>pulse</span> in " \
        "<span class='provider'>Monday</span>",
      title: 'Get item',
      help: 'Retrieves an item by ID in Monday.com',

      config_fields: [
        { name: 'board_id', control_type: :select, label: 'Board', optional: false,
          pick_list: 'boards', change_on_blur: true, extends_schema: true }
      ],

      input_fields: lambda do |_object_definitions|
        [
          { name: 'item_id', label: 'Item ID', optional: false,
            toggle_hint: 'Item ID', toggle_field: {
              name: 'item_id',
              label: 'Item ID',
              type: :string,
              control_type: 'text',
              optional: false,
              toggle_hint: 'Use custom value'
            } }
        ]
      end,

      execute: lambda do |_connection, input|
        result = post('https://api.monday.com/v2').
                 payload(query: %/{items(ids:#{input['item_id']}){/ +
                      'id, name, board{id}, column_values{id, text, '\
                      'value, type, title}, created_at,' \
                      'creator_id, group{id,title}, state, '\
                      'subscribers{id}, updated_at, updates{id}}}')
        item = result['data']['items'][0] || {}
        column_values = {}
        if item.present?
          item['column_values']&.each do |column_value|
            column_value['value'] = if column_value['type'] == 'numeric'
                                      if column_value['value'].present?
                                        column_value['value'].gsub(/"/,
                                                                   '').to_f
                                      else
                                        column_value['value']
                                      end
                                    elsif column_value['type'] == 'text'
                                      if column_value['value'].present?
                                        column_value['value'].gsub(/"/,
                                                                   '')
                                      else
                                        column_value['value']
                                      end
                                    elsif column_value['value'].present?
                                      parse_json(column_value['value'])
                                    else
                                      column_value['value']
                                    end

            column_values[column_value['id']] = column_value
          end
          item['column_values'] = column_values
        end
        item
      end,

      output_fields: lambda do |object_definitions|
        object_definitions['item']
      end,

      sample_output: lambda do |_connection|
        {
          id: '123456',
          name: 'Task name',
          board: {
            id: '123456'
          },
          column_values: {
            text: {
              id: 'text',
              text: 'Done',
              value: 'Done',
              type: 'lookup',
              title: 'Status'
            }
          },
          created_at: '2020-03-10 03:20:38 UTC',
          creator_id: '123456',
          group: {
            id: 'topics',
            title: 'Topics'
          },
          state: 'active',
          subscribers: [
            {
              id: 123_456
            }
          ],
          updated_at: '2020-06-12 11:07:14 UTC',
          updates: [
            {
              id: '123456'
            }
          ]
        }
      end
    },
    create_item: {
      deprecated: true,
      description: "Create a <span class='provider'>pulse</span> on a specific board in " \
        "<span class='provider'>Monday</span>",
      title: 'Create item',
      help: 'Creates an item in a specific group on a specific board',

      config_fields: [
        { name: 'board_id', control_type: :select, label: 'Board', optional: false,
          pick_list: 'boards', change_on_blur: true, extends_schema: true }
      ],

      input_fields: lambda do |object_definitions|
        [
          { name: 'item_name', optional: false }
        ].concat(object_definitions['create_item'].reject { |field| field['name'] == 'name' })
      end,

      execute: lambda do |_connection, input|
        country_names = get('http://country.io/names.json')

        input.each do |_k, v|
          if v.is_a?(Hash) && v.has_key?('countryCode')
            v['countryName'] =
              country_names[v['countryCode']]
          end
        end

        item_details = %(board_id:#{input.delete('board_id')}, ) +
                       %(item_name:"#{input.delete('item_name')}", ) +
                       %(group_id:"#{input.delete('group_id')}", )
        unless input.blank?
          item_details << %(column_values:#{input.to_json.gsub(/("(?=\[))|((?<=\])")|\\/,
                                                               '').to_json})
        end
        {
          item: post('https://api.monday.com/v2').payload(
            query: "mutation{create_item( #{item_details} ){id}}"
          )
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'item', type: 'object',
            properties: [
              { name: 'data', type: 'object',
                properties: [
                  { name: 'create_item', type: 'object',
                    properties: object_definitions['item'] }
                ] },
              { name: 'account_id', type: 'integer', control_type: 'number' }
            ] }
        ]
      end,

      sample_output: lambda do |_connection|
        {
          item: {
            data: {
              create_item: {
                id: 100_000_1
              }
            },
            account_id: 200_000_0
          }
        }
      end
    },
    update_item: {
      deprecated: true,
      description: "Update a <span class='provider'>pulse</span> on a specific board in " \
        "<span class='provider'>Monday</span>",
      title: 'Update item',
      help: 'Updates the values of multiple columns on a specific pulse on a specific board',

      config_fields: [
        { name: 'board_id', control_type: :select, label: 'Board', optional: false,
          pick_list: 'boards', change_on_blur: true, extends_schema: true }
      ],

      input_fields: lambda do |object_definitions|
        [
          { name: 'item_id', type: 'integer', control_type: 'number', optional: false,
            parse_output: 'integer_conversion', render_input: 'integer_conversion' }
        ].concat(object_definitions['create_item'].reject { |field| field['name'] == 'group_id' })
      end,

      execute: lambda do |_connection, input|
        country_names = get('http://country.io/names.json')

        input.each do |_k, v|
          if v.is_a?(Hash) && v.has_key?('countryCode')
            v['countryName'] =
              country_names[v['countryCode']]
          end
        end

        item_details = %(board_id:#{input.delete('board_id')}, ) +
                       %(item_id:#{input.delete('item_id')}, ) +
                       %(column_values:#{input.to_json.gsub(/("(?=\[))|((?<=\])")|\\/, '').to_json})

        {
          item: post('https://api.monday.com/v2').payload(
            query: "mutation{change_multiple_column_values ( #{item_details} ){id}}"
          )
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'item', type: 'object',
            properties: [
              { name: 'data', type: 'object',
                properties: [
                  { name: 'change_multiple_column_values', type: 'object',
                    properties: object_definitions['item'] }
                ] },
              { name: 'account_id', type: 'integer', control_type: 'number' }
            ] }
        ]
      end,

      sample_output: lambda do |_connection|
        {
          item: {
            data: {
              change_multiple_column_values: {
                id: 100_000_1
              }
            },
            account_id: 200_000_0
          }
        }
      end
    },
    create_update: {
      deprecated: true,
      description: "Add an update to a <span class='provider'>pulse</span> in " \
        "<span class='provider'>Monday</span>",
      title: 'Create update',
      help: 'Creates an update on a specific item',

      input_fields: lambda do |_object_definitions|
        [
          { name: 'item_id', type: 'integer', control_type: 'number', optional: false,
            parse_output: 'integer_conversion', render_input: 'integer_conversion' },
          { name: 'body', optional: false }
        ]
      end,

      execute: lambda do |_connection, input|
        item_details = %(item_id:#{input['item_id']}, ) +
                       %(body:"#{input['body']}")

        {
          item: post('https://api.monday.com/v2').payload(
            query: "mutation{create_update (#{item_details}){id}}"
          )
        }
      end,

      output_fields: lambda do |object_definitions|
        [
          { name: 'item', type: 'object',
            properties: [
              { name: 'data', type: 'object',
                properties: [
                  { name: 'create_update', type: 'object',
                    properties: object_definitions['update'] }
                ] },
              { name: 'account_id', type: 'integer', control_type: 'number' }
            ] }
        ]
      end,

      sample_output: lambda do |_connection|
        {
          item: {
            data: {
              create_update: {
                id: 100_000_1
              }
            },
            account_id: 200_000_0
          }
        }
      end
    },
    move_item_to_group: {
      deprecated: true,
      description: "Move a <span class='provider'>pulse</span> in " \
        "<span class='provider'>Monday</span> to a different group",
      title: 'Move item to group',
      help: 'Moves an item from one group to another on the same board',

      config_fields: [
        { name: 'item_id', type: 'integer',
          control_type: 'number', optional: false,
          parse_output: 'integer_conversion',
          render_input: 'integer_conversion' }
      ],

      input_fields: lambda do |object_definitions|
        object_definitions['move_item_to_group']
      end,

      execute: lambda do |_connection, input|
        item_details = %(item_id:#{input['item_id']}, group_id:#{input['group_id']})

        {
          item: post('https://api.monday.com/v2').payload(
            query: "mutation{move_item_to_group ( #{item_details} ){id}}"
          )
        }
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'item', type: 'object', properties: [
            { name: 'data', type: 'object', properties: [
              { name: 'move_item_to_group',
                type: 'object',
                properties: [
                  { name: 'id', type: 'integer', control_type: 'number' }
                ] }
            ] },
            { name: 'account_id', type: 'integer', control_type: 'number' }
          ] }
        ]
      end,

      sample_output: lambda do |_connection|
        {
          item: {
            data: {
              move_item_to_group: {
                id: 100_000_1
              }
            },
            account_id: 200_000_0
          }
        }
      end
    },
    archive_item: {
      deprecated: true,
      description: "Archive a <span class='provider'>pulse</span> in " \
        "<span class='provider'>Monday</span>",
      title: 'Archive item',
      help: 'Archives a specific item',

      input_fields: lambda do |_object_definitions|
        [
          { name: 'item_id', type: 'integer', control_type: 'number', optional: false,
            parse_output: 'integer_conversion', render_input: 'integer_conversion' }
        ]
      end,

      execute: lambda do |_connection, input|
        {
          item: post('https://api.monday.com/v2').payload(
            query: "mutation{archive_item (item_id:#{input['item_id']}){id}}"
          )
        }
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'item', type: 'object', properties: [
            { name: 'data', type: 'object', properties: [
              { name: 'archive_item', type: 'object',
                properties: [
                  { name: 'id', type: 'integer', control_type: 'number' }
                ] }
            ] },
            { name: 'account_id', type: 'integer', control_type: 'number' }
          ] }
        ]
      end,

      sample_output: lambda do |_connection|
        {
          item: {
            data: {
              archive_item: {
                id: 100_000_1
              }
            },
            account_id: 200_000_0
          }
        }
      end
    },
    delete_item: {
      deprecated: true,
      description: "Delete a <span class='provider'>pulse</span> in " \
        "<span class='provider'>Monday</span>",
      title: 'Delete item',
      help: 'Deletes a specific item',

      input_fields: lambda do |_object_definitions|
        [
          { name: 'item_id', type: 'integer', control_type: 'number', optional: false,
            parse_output: 'integer_conversion', render_input: 'integer_conversion' }
        ]
      end,

      execute: lambda do |_connection, input|
        {
          item: post('https://api.monday.com/v2').payload(
            query: "mutation{delete_item (item_id:#{input['item_id']}){id}}"
          )
        }
      end,

      output_fields: lambda do |_object_definitions|
        [
          { name: 'item', type: 'object',
            properties: [
              { name: 'data', type: 'object',
                properties: [
                  { name: 'delete_item', type: 'object',
                    properties: [
                      { name: 'id', type: 'integer', control_type: 'number' }
                    ] }
                ] },
              { name: 'account_id', type: 'integer', control_type: 'number' }
            ] }
        ]
      end,

      sample_output: lambda do |_connection|
        {
          item: {
            data: {
              delete_item: {
                id: 100_000_1
              }
            },
            account_id: 200_000_0
          }
        }
      end
    }
  },

  triggers: {
    new_item: {
      title: 'New item',
      subtitle: 'Triggers when a Item is created in Monday.com',
      description: lambda do |_connection|
        "New <span class='provider'>" \
        "Item</span> in <span class='provider'>Monday.com</span>"
      end,
      help: lambda do |_connection, _input|
        'Triggers when Item is created in Monday.com.'
      end,
      config_fields: [
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],
      input_fields: lambda do |object_definition|
        object_definition['new_item_trigger_input']
      end,
      output_fields: lambda do |object_definition|
        object_definition['new_item_trigger_output']
      end,
      poll: lambda do |_connection, input, closure|
        limit = 1000
        page = closure&.[]('page') || 1
        from =
          (closure&.[]('from') || input['since'] || 1.hour.ago).to_time.
          utc.iso8601
        to = (closure&.[]('to') || Time.now).to_time.utc.iso8601
        params = "from:  \"#{from}\", to: \"#{to}\", limit: #{limit},
                  page:#{page}"
        payload = { query: "query { boards (ids: #{input['board_id'].to_i}) {
             activity_logs (#{params}) {
               id created_at event data entity account_id user_id
             } } }" }
        response = post('', payload).
                   after_response do |_code, body, _headers|
                     if body['errors'].present?
                       error(body.dig('errors', 0, 'message'))
                     elsif body['error_code'].present? || body['error_message'].present?
                       error(body['error_message'])
                     else
                       body
                     end
                   end
        response = response.after_error_response(/.*/) do |_code, body, _header, message|
          error("#{message}: #{body}")
        end&.dig('data', 'boards', 0, 'activity_logs')
        closure = if (more_records = (response&.count || 0) >= limit)
                    { page: page + 1, from: from, to: to }
                  else
                    { page: 1, from: to, to: Time.now }
                  end
        result = response&.select do |record|
          record['event'] == 'create_pulse'
        end&.compact
        {
          events: call('format_output', result),
          next_poll: closure,
          can_poll_more: more_records
        }
      end,
      dedup: lambda do |object|
        "#{object['id']}@#{object['created_at']}@#{object['event']}"
      end
    },
    updated_any_column_value: {
      title: 'Updated any column value',
      subtitle: 'Triggers when any column value is updated in Monday.com',
      description: lambda do |_connection|
        "Updated <span class='provider'>" \
        "Any column value</span> in <span class='provider'>Monday.com</span>"
      end,
      help: lambda do |_connection, _input|
        'Triggers when any column value is updated in Monday.com.'
      end,
      config_fields: [
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],
      input_fields: lambda do |object_definition|
        object_definition['new_item_trigger_input']
      end,
      output_fields: lambda do |_object_definition|
        [
          { name: 'item_id', type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' }
        ]
      end,
      poll: lambda do |_connection, input, closure|
        limit = 1000
        page = closure&.[]('page') || 1
        item_id = closure&.[]('item_id') || []
        from =
          (closure&.[]('from') || input['since'] || 1.hour.ago).to_time.
          utc.iso8601
        to = (closure&.[]('to') || Time.now).to_time.utc.iso8601
        params = "from:  \"#{from}\", to: \"#{to}\", limit: #{limit},
                  page:#{page}"
        payload = { query: "query { boards (ids: #{input['board_id'].to_i}) {
             activity_logs (#{params}) {
               id created_at event data entity account_id user_id
             } } }" }
        response = post('', payload).
                   after_response do |_code, body, _headers|
                     if body['errors'].present?
                       error(body.dig('errors', 0, 'message'))
                     elsif body['error_code'].present? || body['error_message'].present?
                       error(body['error_message'])
                     else
                       body
                     end
                   end
        response = response.after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end&.dig('data', 'boards', 0, 'activity_logs')&.select do |record|
                     record['event'] == 'update_column_value'
                   end&.compact
        response = call('format_output', response)
        item_id = response&.map do |item|
          item_id.concat([item&.dig('data', 'pulse_id')])&.compact
        end&.flatten&.uniq
        closure = if (more_records = (response&.count || 0) >= limit)
                    { page: page + 1, from: from, to: to, item_id: item_id }
                  else
                    { page: 1, from: to, to: Time.now, item_id: item_id }
                  end
        result = if item_id.present? && !more_records
                   item_id&.map do |item|
                     {
                       item_id: item
                     }
                   end
                 else
                   []
                 end
        {
          events: result,
          next_poll: closure,
          can_poll_more: more_records
        }
      end,
      dedup: lambda do |object|
        "#{object['item_id']}@#{Time.now}"
      end
    },
    updated_column_value: {
      title: 'Updated specific column value',
      subtitle: 'Triggers when a specific column value is updated in Monday.com',
      description: lambda do |_connection|
        "Updated <span class='provider'>" \
        "Column value</span> in <span class='provider'>Monday.com</span>"
      end,
      help: lambda do |_connection, _input|
        'Triggers when specific column value is updated in Monday.com.'
      end,
      config_fields: [
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],
      input_fields: lambda do |object_definition|
        object_definition['updated_column_value_trigger_input']
      end,
      output_fields: lambda do |object_definition|
        object_definition['updated_column_value_trigger_output']
      end,
      poll: lambda do |_connection, input, closure|
        limit = 1000
        page = closure&.[]('page') || 1
        from =
          (closure&.[]('from') || input['since'] || 1.hour.ago).to_time.
          utc.iso8601
        to = (closure&.[]('to') || Time.now).to_time.utc.iso8601
        params = "from: \"#{from}\", to: \"#{to}\", limit: #{limit},
                  page:#{page}, column_ids: \"#{input['column_id']}\""
        payload = { query: "query { boards (ids: #{input['board_id'].to_i}) {
             activity_logs (#{params}) {
               id created_at event data entity account_id user_id
             } } }" }
        response = post('', payload).
                   after_response do |_code, body, _headers|
                     if body['errors'].present?
                       error(body.dig('errors', 0, 'message'))
                     elsif body['error_code'].present? || body['error_message'].present?
                       error(body['error_message'])
                     else
                       body
                     end
                   end
        response = response.after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end&.dig('data', 'boards', 0, 'activity_logs')
        closure = if (more_records = (response&.count || 0) >= limit)
                    { page: page + 1, from: from, to: to }
                  else
                    { page: 1, from: to, to: Time.now }
                  end
        result = response&.select do |record|
          record['event'] == 'update_column_value'
        end&.compact
        {
          events: call('format_output', result),
          next_poll: closure,
          can_poll_more: more_records
        }
      end,
      dedup: lambda do |object|
        "#{object['id']}@#{object['created_at']}@#{object['event']}"
      end
    },
    moved_item: {
      title: 'New moved item to group',
      subtitle: 'Triggers when a Item moved to a group in Monday.com',
      description: lambda do |_connection|
        "New <span class='provider'>" \
        "Moved item to a group</span> in <span class='provider'>Monday.com</span>"
      end,
      help: lambda do |_connection, _input|
        'Triggers when Item is moved to a group in Monday.com.'
      end,
      config_fields: [
        {
          ngIf: 'false',
          name: 'recipe_api_version',
          default: '2023-07'
        }
      ],
      input_fields: lambda do |object_definition|
        object_definition['item_moved_trigger_input']
      end,
      output_fields: lambda do |object_definition|
        object_definition['item_moved_trigger_output']
      end,
      poll: lambda do |_connection, input, closure|
        limit = 1000
        page = closure&.[]('page') || 1
        from =
          (closure&.[]('from') || input['since'] || 1.hour.ago).to_time.
          utc.iso8601
        to = (closure&.[]('to') || Time.now).to_time.utc.iso8601
        params = "from:  \"#{from}\", to: \"#{to}\", limit: #{limit},
                 page:#{page}, group_ids: \"#{input['group_id']}\""
        payload = { query: "query { boards (ids: #{input['board_id'].to_i}) {
             activity_logs (#{params}) {
               id created_at event data entity account_id user_id
             } } }" }
        response = post('', payload).
                   after_response do |_code, body, _headers|
                     if body['errors'].present?
                       error(body.dig('errors', 0, 'message'))
                     elsif body['error_code'].present? || body['error_message'].present?
                       error(body['error_message'])
                     else
                       body
                     end
                   end
        response = response.after_error_response(/.*/) do |_code, body, _header, message|
                     error("#{message}: #{body}")
                   end&.dig('data', 'boards', 0, 'activity_logs')
        closure = if (more_records = (response&.count || 0) >= limit)
                    { page: page + 1, from: from, to: to }
                  else
                    { page: 1, from: to, to: Time.now }
                  end
        result = response&.select do |record|
          record['event'] == 'move_pulse_into_group'
        end&.compact
        {
          events: call('format_output', result),
          next_poll: closure,
          can_poll_more: more_records
        }
      end,
      dedup: lambda do |object|
        "#{object['id']}@#{object['created_at']}@#{object['event']}"
      end
    }
  },

  methods: {

    ###############################################################
    ### Methods required for 'custom_operation' action

    execute_custom_operation: lambda do |connection, input, eis, _eos|
      # get variable input data
      variables = {}
      eis&.each do |field|
        field_name = field['name']
        next unless field_name.starts_with?('variable_')

        # strip for 9 characters
        variable_name = field_name[9..-1]

        variable_value = input&.[]("variable_#{variable_name}")
        variables[variable_name] = variable_value
      end
      call(
        'run_gql',
        connection,
        input['query'],
        input['operation_name'],
        variables
      )
    end,
    parse_graphql_type: lambda do |_connection, _messages, type_string|
      m = type_string&.strip&.match(
        /(?<is_list>\[\s*)?(?<name>\w+)(?<required_1>!)?(?<end_list>\s*\])?(?<required_2>!)?/m
      )
      unless m.nil?
        {
          is_list: m['is_list'].present?,
          name: m['name'],
          is_optional: if m['is_list'].blank?
                         m['required_1'].blank?
                       else
                         m['required_2'].blank?
                       end
        }.compact
      end
    end,
    parse_graphql_variables: lambda do |connection, messages, variables_string|
      variables = variables_string&.strip&.scan(
        /\$(\w+)\s*:\s*((\w|\[|\]|!)+)\s*(=\s*(.+?))?[,)]/
      )
      variables&.map do |variable|
        type_string = variable[1]
        type = call(
          'parse_graphql_type',
          connection,
          messages,
          type_string
        )
        if type.nil?
          messages&.call("Could not parse type '#{type_string}'")
          next
        end
        {
          name: variable[0],
          type: type,
          default: variable[4]
        }.compact
      end&.compact
    end,
    parse_graphql_fields: lambda do |connection, report_problem, fields_string|
      fields_string = fields_string&.gsub(/\.\.\.on/, '... on')
      fields = fields_string&.scan(
        /(?<options>
           (?<fragmentRef>
             \.\.\.(?<fragmentName>\w+)
           )|
           (?<field>
             (?<fieldAlias>(?<fieldAliasName>\w+)\s*:\s*)?(?<fieldName>\w+)\s*
             (?<fieldArgs>\(.+?\))?\s*
             (?<fieldFields>{
               (?<fieldFieldsInner>[^{}]|\g<fieldFields>)*
             })?
           )|
           (?<inlineFragment>
           \.\.\.\s*on\s+(?<inlineFragmentType>\w+)\s*
            (?<inlineFragmentFields>{
              (?<inlineFragmentFieldsInner>[^{}]|\g<inlineFragmentFields>)*
            })
          )
         )/mx
      )
      fields&.map do |field|
        if field[6].present? # fieldName
          {
            name: field[6], # fieldName
            alias: field[5], # fieldAlias
            fields: call(
              'parse_graphql_fields',
              connection,
              report_problem,
              field[8] # fieldFields
            )
          }.compact
        elsif field[2].present? # fragmentName
          {
            fragment_name: field[2] # fragmentName
          }.compact
        elsif field[11].present? # inlineFragmentType
          {
            fragment_type: field[11], # inlineFragmentType
            fields: call(
              'parse_graphql_fields',
              connection,
              report_problem,
              field[12] # inlineFragmentFields
            )&.compact
          }
        else
          report_problem&.call 'Unexpacted field syntax'
        end
      end&.flatten(1)&.compact
    end,
    parse_graphql: lambda do |connection, report_problem, query|
      # replace datapills by dummy values
      query = query&.gsub(/#\{(?:_dp|_)?\(.+\)\}/, 'datapill')

      # replace single-line comments
      query = query&.gsub(%r{//.*$}, '')
      query = query&.gsub(/#.*$/, '')

      # parse groups
      groups = query&.scan(/(?<group>[^{}]*(?<fields>{(?<inner>[^{}]|\g<fields>)*})?)/m)

      # parse operations
      operations = groups&.map do |group|
        group = group[0]
        m = group.match(/^\s*(?<type_and_Rest>
                           (?<operation_type>query|mutation)\s*
                           (?<name_and_rest>
                            (?<operation_name>\w+)\s*
                            (?<variables>\(.+?\))?\s*
                            )?
                         )?\s*
                         (?<fields>{.+}\s*$)/mxsu)
        next if m.nil?

        operation_type = m['operation_type']

        operation_type = 'query' if operation_type.blank?
        unless %w[query mutation].include? operation_type
          report_problem&.call "Unsupported operation type '#{operation_type}'"
          next
        end

        {
          operation_type: operation_type,
          operation_name: m['operation_name'],
          variables: call(
            'parse_graphql_variables',
            connection,
            report_problem,
            m['variables']
          ),
          fields: call(
            'parse_graphql_fields',
            connection,
            report_problem,
            m['fields']
          )
        }.compact
      end&.compact

      # parse fragments
      fragments = groups&.map do |group|
        group = group[0]
        m = group.match(/^\s*fragment\s*
                         (?<fragment_name>\w+)\s+
                         on\s+
                         (?<fragment_type>\w+)\s*
                         {(?<fields>.+)}\s*$/mxsu)
        next if m.nil?

        {
          name: m['fragment_name'],
          type: m['fragment_type'],
          fields: call(
            'parse_graphql_fields',
            connection,
            report_problem,
            m['fields']
          )
        }.compact
      end&.compact

      # return parsed query
      {
        operations: operations,
        fragments: fragments
      }
    end,
    create_custom_operation_output_fields: lambda do |
                                connection,
                                document,
                                report_problem,
                                operation
                                |
      operation_type = call(
        'get_operation_type',
        connection,
        operation[:operation_type]
      )
      if operation_type.nil?
        report_problem&.call "Could not find #{operation[:operation_type]} operation type"
      end
      if operation_type.present?
        operation[:fields]&.map do |field|
          call(
            'create_custom_operation_output_field',
            connection,
            document,
            report_problem,
            operation,
            operation_type,
            field
          )
        end&.flatten(1)&.compact
      end
    end,
    create_custom_operation_output_field: lambda do
      |
      connection,
      document,
      report_problem,
      operation,
      parent_type,
      field
      |

      # field
      if field[:name] == '__typename'
        output_field = {
          name: '__typename',
          type: :string,
          label: 'Type name'
        }
      elsif field[:name].present?
        field_from_type = parent_type['fields']&.find do |f|
          f['name'] == field[:name]
        end
        report_problem&.call "Could not find field '#{field[:name]}'" if field_from_type.nil?
      end
      if field_from_type.present?
        # create workato schema field
        output_field = call(
          'create_output_field_for_type',
          connection,
          field_from_type['type'],
          field[:name]
        )
        call(
          'apply_field_name_and_label',
          connection,
          output_field,
          nil,
          field[:alias] || field[:name]
        )

        # strip non_null and list to get the inner type
        field_type = call(
          'get_inner_type',
          field_from_type['type']
        )
        field_type = call(
          'get_schema_type',
          connection,
          report_problem,
          field_type['kind'],
          field_type['name']
        )

        # map fields to properties
        output_field[:properties] = field[:fields]&.map do |sub_field|
          call(
            'create_custom_operation_output_field',
            connection,
            document,
            report_problem,
            operation,
            field_type,
            sub_field
          )
        end&.flatten(1)&.compact

        output_field = output_field.compact
      end

      # fragment
      if field[:fragment_name].present?
        fragment = document[:fragments]&.find do |f|
          f[:name] == field[:fragment_name]
        end
        if fragment.nil?
          report_problem&.call "Could not find fragment named '#{field[:fragment_name]}'"
        else
          fragment_type = call(
            'get_schema_type',
            connection,
            report_problem,
            'OBJECT',
            fragment[:type]
          )
        end
        if fragment.present? && fragment_type.nil?
          report_problem&.call "Could not fragment type '#{fragment[:type]}'"
        end
      end
      if field[:fragment_type].present? # inline fragment
        fragment_type = call(
          'get_schema_type',
          connection,
          report_problem,
          'OBJECT',
          field[:fragment_type]
        )
        if fragment_type.nil?
          report_problem&.call "Could not inline fragment type '#{field[:fragment_type]}'"
        end
        fragment = field
      end
      if fragment.present? && fragment_type.present?
        output_field = fragment[:fields]&.map do |sub_field|
          call(
            'create_custom_operation_output_field',
            connection,
            document,
            report_problem,
            operation,
            fragment_type,
            sub_field
          )
        end&.flatten(1)&.compact
      end

      output_field
    end,
    create_custom_operation_variables_input_fields: lambda do |
      connection,
      _document,
      report_problem,
      operation|
      operation[:variables]&.map do |variable|
        next if variable.nil?

        variable[:optional] = true unless variable.has_key?(:optional)
        type_name = variable.dig(:type, :name)
        variable_type = call(
          'get_schema_type',
          connection,
          report_problem,
          nil,
          type_name
        )
        if variable_type.nil?
          report_problem&.call "Could not get '#{type_name}' schema type."
          next
        end
        variable_field = call(
          'create_field_for_type',
          connection,
          report_problem,
          variable_type,
          0
        )
        call(
          'apply_field_name_and_label',
          connection,
          variable_field,
          'variable',
          variable[:name]
        )
        default_value = variable[:default]
        variable_field[:hint] = "Defaults to #{default_value}" if default_value.present?
        is_optional = variable.dig(:type, :is_optional)
        is_optional = true if is_optional.nil?
        variable_field[:optional] = is_optional
        if variable.dig(:type, :is_list)
          variable_field[:of] = variable_field[:type]
          variable_field.delete(:control_type)
          variable_field[:type] = :array
        end
        variable_field
      end&.compact
    end,
    get_error_message: lambda do |connection, response|
      message = nil
      if response.is_a?(Hash)
        keys = %w[error_message error_messages message messages
                  error errors error_code error_codes
                  status status_code status_codes code codes]
        keys.each do |key|
          value = response[key]
          next if value.nil? || message.present?

          message = call('get_error_message', connection, value)
        end
      elsif response.is_a?(Array)
        messages = response.map do |value|
          call('get_error_message', connection, value)
        end.compact
        message = messages.join("\n") if messages.present?
      elsif response.is_a?(String)
        value = response.strip
        message = value if value.present?
      end
      message
    end,
    run_gql: lambda do |connection, document, operation_name, variables|
      payload = {
        'query' => document,
        'operationName' => operation_name.presence,
        'variables' => variables
      }.compact
      request = post('')
      request = request.payload(payload)
      handle_errors = lambda do |response|
        error = call('get_error_message', connection, response)
        error(error) if error.present?
      end
      request = request.after_error_response('.*') do |_code, body, header, message|
        content_type = header['content_type'] || ''
        if content_type.include?('application/json')
          response = workato.parse_json(body)
          handle_errors.call(response)
        end
        error("#{message}: #{body}")
      end
      # for some reason, 301 was not handles without 'follow_redirection' (AG)
      request.follow_redirection.after_response do |_code, body, _res_headers|
        handle_errors.call(body)
        body['data']
      end
    end,
    get_schema: lambda do |connection|
      unless connection.has_key?('__schema')
        schema = call(
          'run_gql',
          connection,
          "{
            __schema {
              queryType {
                name
              }
              mutationType {
                name
              }
              types {
                kind
                name
                description
                fields {
                  name
                  description
                  args {
                    name
                    description
                    type {
                      ...typeReference
                    }
                    defaultValue
                  }
                  type {
                    ...typeReference
                  }
                }
                inputFields {
                  name
                  description
                  type {
                    ...typeReference
                  }
                  defaultValue
                }
                enumValues {
                  name
                  description
                }
                possibleTypes {
                  ... typeReference
                }
              }
            }
          }

          fragment typeReference on __Type {
            name
            kind
            ofType {
              name
              kind
              ofType {
                name
                kind
                ofType {
                  name
                  kind
                }
              }
            }
          }
          ",
          nil,
          nil
        )
        connection['__schema'] = schema
      end
      connection['__schema']
    end,
    labelize: lambda do |name|
      name = name&.to_s
      # replace all non-word characters with a space
      name = name&.gsub(/\W|-|_/, ' ')
      name = name&.strip
      name = name&.gsub(/([a-z])([A-Z])/, '\1 \2')
      name = name&.gsub(/[A-Z][a-z]+/) { |word| word.downcase }
      name = name&.gsub(/^\w/) { |word| word.upcase }
      name = name&.gsub(/ id$/, ' ID')
      name = name&.gsub(/ id /, ' ID ')
      name = name&.gsub(/^id /, 'ID ')
      name = name&.gsub(/^id$/, 'ID')
      name
    end,
    get_schema_type: lambda do |connection, report_problem, kind, name|
      schema = call('get_schema', connection)
      types = schema.dig(
        '__schema',
        'types'
      )
      type = types.find do |t|
        t['name'] == name &&
          (kind.nil? || t['kind'] == kind)
      end
      if type.nil?
        if kind.nil?
          report_problem&.call "Could not find type '#{name}'"
        else
          report_problem&.call "Could not find #{kind} type '#{name}'"
        end
      end
      type
    end,
    create_field_for_type: lambda do |connection, report_problem, type, nesting_level|
      field = {
        optional: true
      }
      case type['kind']
      when 'NON_NULL'
        field = call(
          'create_field_for_type',
          connection,
          report_problem,
          type['ofType'],
          nesting_level
        )
        field[:optional] = false
      when 'SCALAR'
        case type['name']
        when 'Boolean'
          field[:type] = :boolean
          field[:control_type] = :checkbox
          field[:convert_input] = :boolean_conversion
          field = field.deep_merge(
            {
              type: :boolean,
              control_type: :checkbox,
              convert_input: :boolean_conversion,
              toggle_hint: 'Pick value',
              toggle_field: {
                type: :boolean,
                control_type: :text,
                convert_input: :boolean_conversion,
                toggle_hint: 'Provide value'
              }
            }
          )
        when 'Float'
          field[:type] = :number
          field[:control_type] = :number
          field[:convert_input] = :float_conversion
        when 'Int', 'Int16', 'Int32', 'Int64', 'UInt', 'UInt16', 'UInt32', 'UInt64', 'Long',
          'ULong', 'NonNegativeInt', 'PositiveInt'
          field[:type] = :integer
          field[:control_type] = :integer
          field[:convert_input] = :integer_conversion
        when 'Date', 'GraphQLDate'
          field = field.deep_merge(
            {
              type: :date,
              control_type: :date,
              convert_input: :date_conversion,
              toggle_hint: 'Pick date',
              toggle_field: {
                type: :date,
                control_type: :text,
                convert_input: :date_conversion,
                toggle_hint: 'Provide value'
              }
            }
          )
        when 'Time', 'GraphQLTime'
          field = field.deep_merge(
            {
              type: :timestamp,
              control_type: :date_time,
              convert_input: :integer_conversion,
              toggle_hint: 'Pick date and time',
              toggle_field: {
                type: :timestamp,
                control_type: :text,
                convert_input: :integer_conversion,
                toggle_hint: 'Provide value'
              }
            }
          )
        when 'DateTime', 'ISO8601DateTime', 'GraphQLDateTime'
          field = field.deep_merge(
            {
              type: :date_time,
              control_type: :date_time,
              convert_input: :render_iso8601_timestamp,
              toggle_hint: 'Pick date and time',
              toggle_field: {
                type: :date_time,
                control_type: :text,
                convert_input: :render_iso8601_timestamp,
                toggle_hint: 'Provide value'
              }
            }
          )
        else # 'String', 'ID', ...
          field = field.merge(
            {
              type: :string,
              control_type: :text
            }
          )
        end
      when 'ENUM'
        enum_type = call(
          'get_schema_type',
          connection,
          report_problem,
          'ENUM',
          type['name']
        )
        pick_list = enum_type&.[]('enumValues')&.map do |e|
          [
            call('labelize', e['name']),
            e['name']
          ]
        end
        field = field.merge(
          {
            type: :string,
            control_type: :select,
            pick_list: pick_list,
            toggle_hint: 'Select from list'
          }
        )
        call(
          'apply_field_description',
          connection,
          field,
          enum_type['description']
        )
        field[:toggle_field] = field.merge(
          {
            type: :string,
            control_type: :text,
            pick_list: nil,
            optional: nil,
            toggle_hint: 'Provide value'
          }
        ).compact
      when 'INPUT_OBJECT'
        field[:type] = :object
        input_object_type = call(
          'get_schema_type',
          connection,
          report_problem,
          'INPUT_OBJECT',
          type['name']
        )
        call(
          'apply_field_description',
          connection,
          field,
          input_object_type&.[]('description')
        )
        if nesting_level < 5
          input_fields = input_object_type&.[]('inputFields') || []
          field[:properties] = input_fields.map do |input_field|
            call(
              'create_field_for_input_field',
              connection,
              report_problem,
              input_field,
              nesting_level + 1
            )
          end
        end
      when 'LIST'
        item_field = call(
          'create_field_for_type',
          connection,
          report_problem,
          type['ofType'],
          nesting_level + 1
        )
        if call('is_enum_type', type['ofType'])
          field = item_field
          field[:control_type] = :multiselect
          field[:optional] = 'false'
          field[:delimiter] = ','
          field[:toggle_field][:type] = :array
          field[:toggle_field][:of] = :string
          field[:toggle_field][:toggle_hint] = 'Provide values'
        else
          field[:type] = :array
          field[:of] = item_field[:type]
          field[:hint] = item_field[:hint]
          field[:properties] = item_field[:properties]
          field[:list_mode] = :static
        end
      else
        error("Unsupported kind '#{type['kind']}'")
      end
      field[:toggle_field][:optional] = field[:optional] if field.has_key?(:toggle_field)
      field
    end,
    apply_field_name_and_label: lambda do |_connection, field, name_prefix, name|
      field[:name] = if name_prefix.blank?
                       name
                     else
                       "#{name_prefix}_#{name}"
                     end
      field[:label] = call('labelize', name)
      toggle_field = field[:toggle_field]
      if toggle_field.present?
        toggle_field[:name] = field[:name]
        toggle_field[:label] = field[:label]
      end
      field
    end,
    apply_field_description: lambda do |connection, field, description|
      unless description.blank?
        field[:hint] = call(
          'format_field_hint',
          connection,
          description
        )
      end
    end,
    get_operation_type: lambda do |connection, operation_type|
      schema = call('get_schema', connection)

      # get operation type name
      operation_type_name = schema.dig(
        '__schema',
        "#{operation_type}Type",
        'name'
      )

      # get operation type
      unless operation_type_name.blank?
        call(
          'get_schema_type',
          connection,
          nil,
          'OBJECT',
          operation_type_name
        )
      end
    end,
    create_field_for_input_field: lambda do |connection, report_problem, input_field, nesting_level|
      field = call(
        'create_field_for_type',
        connection,
        report_problem,
        input_field['type'],
        nesting_level
      )
      call(
        'apply_field_name_and_label',
        connection,
        field,
        nil,
        input_field['name']
      )
      call(
        'apply_field_description',
        connection,
        field,
        input_field['description']
      )
      call(
        'apply_field_default_value',
        connection,
        report_problem,
        field,
        input_field['defaultValue']
      )
      field
    end,
    format_field_hint: lambda do |connection, description|
      if description.present?
        description = description.strip
        description = description.gsub('<p>', '<br>')
        description = description.gsub('</p>', '<br>')
        description = description.gsub(/\R/, '<br>')
        description = description.gsub('\\n', '<br>')

        allow_multi_paragraph_hint = false # call('get_allow_multi_paragraph_hint', connection)
        first_break_index_one = description.index('<br>')
        first_break_index_two = description.index('<br/>')
        if !first_break_index_one.nil? && !first_break_index_two.nil?
          first_break_index = [first_break_index_one, first_break_index_two].min
        elsif first_break_index_one.nil? && !first_break_index_two.nil?
          first_break_index = first_break_index_two
        elsif !first_break_index_one.nil? && first_break_index_two.nil?
          first_break_index = first_break_index_one
        end
        unless first_break_index.nil? || allow_multi_paragraph_hint
          description = description[0..first_break_index - 1]
          description = description.strip
          description = description.gsub(/(.*)\W$/, '\1')
          documentation_href = nil
          if documentation_href.blank?
            documentation_href = nil # call('get_documentation_href', connection)
          end
          if documentation_href&.present?
            anchor = "<a href='#{documentation_href}' target='_blank'>here</a>"
            description = "#{description}. Click #{anchor} for details."
          else
            description = "#{description}. See documentation for details."
          end
        end

        description = description.gsub(/\*\*([^*]+)\*\*/, '<b>\1</b>')
        description = description.gsub(/\*([^*]+)\*/, '<b>\1</b>')
        description = description.gsub(/`([^`]+)`/, '<b>\1</b>')
        description = description.gsub(/'([^']+)'/, '<b>\1</b>')
        description = description.gsub(/"([^"]+)"/, '<b>\1</b>')

        # external links
        external_links = connection.dig('advanced', 'external_links')
        external_links = connection['external_links'] if external_links.nil?
        external_links&.each do |link|
          tag = link['key']
          base_url = link['value']
          next if tag.blank? || base_url.blank?

          description = description.gsub(
            /\[([^\]]+)\]\(#{tag}:([^)]+)\)/,
            "<a href='#{base_url}\\2' target='_blank'>\\1</a>"
          )
        end
        # raw http(s) links
        description = description.gsub(
          /\[([^\]]+)\]\((https?:[^)]+)\)/,
          "<a href='\\2' target='_blank'>\\1</a>"
        )
        # strip remaining links
        description = description.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
      end
      description
    end,
    get_inner_type: lambda do |type|
      case type['kind']
      when 'LIST', 'NON_NULL'
        call('get_inner_type', type['ofType'])
      else
        type
      end
    end,
    create_output_field_for_type: lambda do |connection, type, name|
      field = {}
      case type['kind']
      when 'NON_NULL'
        field = call(
          'create_output_field_for_type',
          connection,
          type['ofType'],
          name
        )
      when 'SCALAR'
        case type['name']
        when 'Boolean'
          field[:type] = :boolean
          field[:convert_output] = :boolean_conversion
        when 'Float'
          field[:type] = :number
          field[:convert_output] = :float_conversion
        when 'Int', 'Int16', 'Int32', 'Int64', 'UInt', 'UInt16', 'UInt32', 'UInt64', 'Long',
          'ULong', 'NonNegativeInt', 'PositiveInt'
          field[:type] = :integer
          field[:convert_output] = :integer_conversion
        when 'Date', 'GraphQLDate'
          if %w[last_activity updated_at created_at ended_at started_at].include?(name)
            field[:type] = :date_time
            field[:control_type] = :date_time
            field[:convert_output] = 'format_date_time_utc'
          else
            field[:type] = :date
            field[:convert_output] = :date_conversion
          end
        when 'Time', 'GraphQLTime'
          field[:type] = :timestamp
          field[:convert_output] = :date_time_conversion
        when 'DateTime', 'ISO8601DateTime', 'GraphQLDateTime'
          field[:type] = :date_time
          field[:convert_output] = :date_time_conversion
        else # 'String', 'ID', ...
          field = field.merge(
            {
              type: :string
            }
          )
        end
      when 'ENUM'
        field = field.merge(
          {
            type: :string
          }
        )
      when 'OBJECT', 'INTERFACE', 'UNION'
        field[:type] = :object
      when 'LIST'
        field[:type] = :array
        item_field = call(
          'create_output_field_for_type',
          connection,
          type['ofType'],
          name
        )
        field[:of] = item_field[:type]
      else
        error("Unsupported kind '#{type['kind']}'")
      end
      field
    end,

    # other action methods
    move_pulse_into_group_output_schema: lambda do
      [
        { name: 'data', type: 'object',
          properties: [
            { name: 'board_id',
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion' },
            { name: 'group_id' },
            { name: 'source_board', type: 'object',
              properties: [
                { name: 'id',
                  type: 'integer', control_type: 'integer',
                  convert_output: 'integer_conversion' },
                { name: 'name' },
                { name: 'kind' }
              ] },
            { name: 'source_group', type: 'object',
              properties: [
                { name: 'id' },
                { name: 'title' },
                { name: 'color' },
                { name: 'is_top_group',
                  type: 'boolean', control_type: 'checkbox',
                  convert_output: 'boolean_conversion' }
              ] },
            { name: 'dest_group', label: 'Destination group',
              type: 'object',
              properties: [
                { name: 'id' },
                { name: 'title' },
                { name: 'color' },
                { name: 'is_top_group',
                  type: 'boolean', control_type: 'checkbox',
                  convert_output: 'boolean_conversion' }
              ] },
            { name: 'pulse', type: 'object',
              properties: [
                { name: 'id',
                  type: 'integer', control_type: 'integer',
                  convert_output: 'integer_conversion' },
                { name: 'name' }
              ] },
            { name: 'action_record_id',
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion' },
            { name: 'is_undo_action',
              type: 'boolean', control_type: 'checkbox',
              convert_output: 'boolean_conversion' },
            { name: 'is_batch_action',
              type: 'boolean', control_type: 'checkbox',
              convert_output: 'boolean_conversion' }
          ] }
      ]
    end,
    create_pulse_output_schema: lambda do
      [
        { name: 'data', type: 'object',
          properties: [
            { name: 'board_id',
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion' },
            { name: 'group_id' },
            { name: 'group_name' },
            { name: 'group_color' },
            { name: 'is_top_group',
              type: 'boolean', control_type: 'checkbox',
              convert_output: 'boolean_conversion' },
            { name: 'pulse_id', label: 'Item ID',
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion' },
            { name: 'pulse_name' }
          ] }
      ]
    end,
    column_value_input_schema: lambda do |input|
      payload = {
        query: "query {boards(ids: #{input['board_id'].to_i}){columns{id,type,title,settings_str}}}"
      }

      create_item_type = %w[formula autonumber columns-battery name]
      create_subitem_type = %w[formula autonumber columns-battery subtasks name]
      update_item_type = %w[formula autonumber columns-battery pulse-log pulse-updated pulse-id]
      columns = post('', payload).after_response do |_code, body, _headers|
        if body['errors'].present?
          error(body.dig('errors', 0, 'message'))
        elsif body['error_code'].present? || body['error_message'].present?
          error(body['error_message'])
        else
          body
        end
      end
      columns.after_error_response(/.*/) do |_code, body, _header, message|
        error("#{message}: #{body}")
      end
      columns&.dig('data', 'boards', 0, 'columns')&.map do |column|
        unless (input['object'] == 'create_item' && create_item_type.include?(column['type'])) ||
               (input['object'] == 'create_subitem' &&
                create_subitem_type.include?(column['type'])) ||
               (input['object'] == 'change_multiple_column_values' &&
                update_item_type.include?(column['type']))
          next nil if %w[mirror file last_updated vote color_picker time_tracking
                         creation_log auto_number button doc progress unsupported
                         item_id subtasks].include?(column['type'])

          case column['type']
          when 'long-text', 'long_text'
            { type: 'object',
              properties: [
                { name: 'text' }
              ] }
          when 'numeric', 'numbers'
            { type: 'number', control_type: 'number' }
          when 'color', 'status'
            { type: 'object',
              properties: [
                { name: 'label', label: column['title'],
                  control_type: :select,
                  pick_list: parse_json(column['settings_str'].to_s)['labels'].
                    map { |_k, v| [v.labelize, v] },
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'label', label: column['title'],
                    type: :string, control_type: 'text',
                    optional: true,
                    toggle_hint: 'Use custom value',
                    hint: 'Enter the label of the value.'
                  } }
              ] }
          when 'dropdown'
            { type: 'object',
              properties: [
                { name: 'labels', label: column['title'],
                  type: 'array', of: 'string',
                  hint: 'Enter the label of the value.' }
              ] }
          when 'team'
            { type: 'object',
              properties: [
                { name: 'team_id',
                  type: 'integer', control_type: 'integer',
                  convert_input: 'integer_conversion' }
              ] }
          when 'multiple-person', 'people'
            { type: 'object',
              properties: [
                { name: 'personsAndTeams', label: column['title'],
                  type: 'array', of: 'object',
                  properties: [
                    { name: 'id', label: 'Person/Team ID',
                      type: 'integer', control_type: 'number',
                      convert_input: 'integer_conversion' },
                    { name: 'kind', label: 'Kind',
                      control_type: :select,
                      pick_list: %w[person team].map { |e| [e.labelize, e] },
                      toggle_hint: 'Select from list',
                      toggle_field: {
                        name: 'kind', label: 'Kind',
                        type: :string, control_type: 'text',
                        optional: true,
                        toggle_hint: 'Use custom value',
                        hint: 'Allowed values are <b>person</b> or <b>team</b>'
                      } }
                  ] }
              ] }
          when 'timezone', 'world_clock'
            { type: 'object',
              properties: [
                { name: 'timezone', label: 'Timezone',
                  control_type: :select,
                  pick_list: 'time_zone',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'timezone', label: 'Timezone',
                    type: :string, control_type: 'text',
                    optional: true,
                    toggle_hint: 'Use custom value'
                  } }
              ] }
          when 'country'
            { type: 'object',
              properties: [
                { name: 'countryCode',
                  control_type: :select,
                  pick_list: 'country_codes',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'countryCode', label: 'Country code',
                    type: :string, control_type: 'text',
                    optional: true,
                    toggle_hint: 'Use custom value'
                  } },
                { name: 'countryName' }
              ] }
          when 'email'
            { type: 'object',
              properties: [
                { name: 'email', control_type: 'email' },
                { name: 'text' }
              ] }
          when 'phone'
            { type: 'object',
              properties: [
                { name: 'phone', control_type: 'phone' },
                { name: 'countryShortName',
                  control_type: :select,
                  pick_list: 'country_codes',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'countryShortName', label: 'Country short name',
                    type: :string, control_type: 'text',
                    optional: true,
                    toggle_hint: 'Use custom value'
                  } }
              ] }
          when 'link'
            { type: 'object',
              properties: [
                { name: 'url', control_type: 'url' },
                { name: 'text' }
              ] }
          when 'date'
            { type: 'object',
              properties: [
                { name: 'date',
                  type: 'date', control_type: 'date',
                  convert_input: 'date_conversion' },
                { name: 'time', type: 'time', control_type: 'time' }
              ] }
          when 'timerange', 'timeline'
            { type: 'object',
              properties: [
                { name: 'from', type: 'date', control_type: 'date',
                  convert_input: 'date_conversion' },
                { name: 'to', type: 'date', control_type: 'date',
                  convert_input: 'date_conversion' }
              ] }
          when 'tag', 'tags'
            { type: 'object',
              properties: [
                { name: 'tag_ids', label: 'Tag IDs',
                  type: 'array', of: 'integer' }
              ] }
          when 'hour'
            { type: 'object',
              properties: [
                { name: 'hour',
                  type: 'integer', control_type: 'integer',
                  convert_input: 'integer_conversion',
                  hint: 'Hour should be in 24-hour format' },
                { name: 'minute',
                  type: 'integer', control_type: 'integer',
                  convert_input: 'integer_conversion' }
              ] }
          when 'week'
            { type: 'object',
              properties: [
                { name: 'week', type: 'object',
                  hint: 'Dates must be 7 days apart, inclusive, and start ' \
                        'on Monday of the given week.',
                  properties: [
                    { name: 'startDate', type: 'date', control_type: 'date',
                      convert_input: 'date_conversion' },
                    { name: 'endDate', type: 'date', control_type: 'date',
                      convert_input: 'date_conversion' }
                  ] }
              ] }
          when 'boolean', 'checkbox'
            { type: 'object',
              properties: [
                { name: 'checked',
                  type: 'boolean', control_type: 'checkbox',
                  toggle_hint: 'Select from list',
                  toggle_field: {
                    name: 'checked', label: 'Checked',
                    type: 'string', control_type: 'text',
                    optional: true,
                    hint: 'Accepted values are true or false',
                    toggle_hint: 'Use custom value'
                  } }
              ] }
          when 'rating'
            { type: 'object',
              properties: [
                { name: 'rating', type: 'integer', control_type: 'integer',
                  convert_input: 'integer_conversion' }
              ] }
          when 'board-relation', 'board_relation'
            { type: 'object',
              properties: [
                { name: 'item_ids', label: 'Item IDs',
                  type: 'array', of: 'integer' }
              ] }
          when 'dependency'
            case call('get_recipe_api_version', input)
            when '2023-07'
              {
                type: 'object',
                properties: [
                  { name: 'item_ids', label: 'Item IDs',
                    type: 'array', of: 'object' }
                ]
              }
            when '2023-10'
              {
                type: 'object',
                properties: [
                  { name: 'item_ids', label: 'Item IDs',
                    type: 'array', of: 'string' }
                ]
              }
            else
              error('Unhandled recipe API version')
            end
          when 'location'
            {
              type: 'object',
              properties: [
                { name: 'lat', label: 'Latitude' },
                { name: 'lng', label: 'Longitude' },
                { name: 'address' }
              ]
            }
          else
            { type: 'string' }
          end&.merge(
            { name: column['id'], label: column['title'] }
          )
        end
      end&.compact
    end,
    update_column_value_output_schema: lambda do |input|
      value_schema = input['column_id'].present? ? call('column_value_output_schema', input) : []
      [
        { name: 'data', type: 'object',
          properties: [
            { name: 'board_id',
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion' },
            { name: 'group_id' },
            { name: 'is_top_group',
              type: 'boolean', control_type: 'checkbox',
              convert_output: 'boolean_conversion' },
            { name: 'pulse_id', label: 'Item ID',
              type: 'integer', control_type: 'integer',
              convert_output: 'integer_conversion' },
            { name: 'pulse_name' },
            { name: 'column_id' },
            { name: 'column_type' },
            { name: 'column_title' },
            { name: 'value',
              type: 'object',
              properties: value_schema },
            { name: 'previous_value',
              type: 'object',
              properties: value_schema },
            { name: 'is_column_with_hide_permissions',
              type: 'boolean', control_type: 'checkbox',
              convert_output: 'boolean_conversion' }
          ] }
      ]
    end,
    column_value_output_schema: lambda do |input|
      payload = {
        query: "query { boards (ids: #{input['board_id'].to_i}) "\
        "{ columns (ids: \"#{input['column_id']}\") { type } } }"
      }
      type = post('', payload)&.dig('data', 'boards', 0, 'columns', 0, 'type')
      case type
      when 'dropdown'
        [
          { name: 'chosenValues',
            type: 'array', of: 'object',
            properties: [
              { name: 'id',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' },
              { name: 'name' }
            ] }
        ]
      when 'date'
        [
          { name: 'date', type: 'date', control_type: 'date',
            convert_output: 'date_conversion' },
          { name: 'icon' },
          { name: 'time' }
        ]
      when 'timerange', 'timeline'
        [
          { name: 'from', type: 'date', control_type: 'date',
            convert_output: 'date_conversion' },
          { name: 'to', type: 'date', control_type: 'date',
            convert_output: 'date_conversion' },
          { name: 'visualization_type' }
        ]
      when 'name'
        [
          { name: 'name' }
        ]
      when 'numeric', 'numbers'
        [
          { name: 'value',
            type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' },
          { name: 'unit' }
        ]
      when 'color', 'status'
        [
          { name: 'label', type: 'object',
            properties: [
              { name: 'index',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' },
              { name: 'text' },
              { name: 'style', type: 'object',
                properties: [
                  { name: 'color' },
                  { name: 'border' },
                  { name: 'var_name' }
                ] },
              { name: 'is_done',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' }
            ] },
          { name: 'post_id' }
        ]
      when 'file', 'files'
        [
          { name: 'files', type: 'array', of: 'object',
            properties: [
              { name: 'fileType' },
              { name: 'assetId',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' },
              { name: 'name' },
              { name: 'isImage',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' }
            ] },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'hide_footer',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' }
            ] }
        ]
      when 'subtasks'
        [
          { name: 'linkedPulseIds', type: 'array', of: 'object',
            properties: [
              { name: 'linkedPulseId',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' }
            ] },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'displayType' },
              { name: 'itemTypeName' },
              { name: 'allowMultipleItems',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' },
              { name: 'boardIds', type: 'array', of: 'integer' }
            ] }
        ]
      when 'boolean', 'checkbox'
        [
          { name: 'checked',
            type: 'boolean', control_type: 'checkbox',
            convert_output: 'boolean_conversion' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'color' }
            ] }
        ]
      when 'text'
        [
          { name: 'value' }
        ]
      when 'multiple-person', 'people'
        [
          { name: 'personsAndTeams', type: 'array', of: 'object',
            properties: [
              { name: 'id',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' },
              { name: 'kind' }
            ] },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'hide_footer',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' }
            ] }
        ]
      when 'board-relation', 'board_relation'
        [
          { name: 'boardIds', label: 'Board IDs',
            type: 'array', of: 'integer' },
          { name: 'linkedPulseIds', label: 'Linked pulse IDs',
            type: 'array', of: 'object',
            properties: [
              { name: 'linkedPulseId', type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' }
            ] },
          { name: 'name' }
        ]
      when 'tag', 'tags'
        [
          { name: 'tags', type: 'array', of: 'object',
            properties: [
              { name: 'id',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' },
              { name: 'name' },
              { name: 'color' }
            ] }
        ]
      when 'votes', 'vote'
        [
          { name: 'voters_ids', label: 'Voters IDs',
            type: 'array', of: 'integer' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'color' }
            ] }
        ]
      when 'hour'
        [
          { name: 'hour',
            type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' },
          { name: 'minute',
            type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' },
          { name: 'changed_at' },
          { name: 'column_settings', type: 'object', properties: [] }
        ]
      when 'email'
        [
          { name: 'email' },
          { name: 'text' },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'includePulseInSubject',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' },
              { name: 'ccPulse',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' },
              { name: 'bccList' }
            ] }
        ]
      when 'duration', 'time_tracking'
        [
          { name: 'startDate',
            type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' },
          { name: 'duration',
            type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' },
          { name: 'running' },
          { name: 'column_settings', type: 'object',
            properties: [] }
        ]
      when 'color-picker', 'color_picker'
        [
          { name: 'color', type: 'object',
            properties: [
              { name: 'hsl', type: 'object',
                properties: [
                  { name: 'h',
                    type: 'number', control_type: 'number',
                    convert_output: 'float_conversion' },
                  { name: 's',
                    type: 'number', control_type: 'number',
                    convert_output: 'float_conversion' },
                  { name: 'l',
                    type: 'number', control_type: 'number',
                    convert_output: 'float_conversion' },
                  { name: 'a',
                    type: 'integer', control_type: 'integer',
                    convert_output: 'integer_conversion' }
                ] },
              { name: 'hex' },
              { name: 'rgb', type: 'object',
                properties: [
                  { name: 'r',
                    type: 'integer', control_type: 'integer',
                    convert_output: 'integer_conversion' },
                  { name: 'g',
                    type: 'integer', control_type: 'integer',
                    convert_output: 'integer_conversion' },
                  { name: 'b',
                    type: 'integer', control_type: 'integer',
                    convert_output: 'integer_conversion' },
                  { name: 'a',
                    type: 'integer', control_type: 'integer',
                    convert_output: 'integer_conversion' }
                ] },
              { name: 'hsv', type: 'object',
                properties: [
                  { name: 'h',
                    type: 'number', control_type: 'number',
                    convert_output: 'float_conversion' },
                  { name: 's',
                    type: 'number', control_type: 'number',
                    convert_output: 'float_conversion' },
                  { name: 'v',
                    type: 'number', control_type: 'number',
                    convert_output: 'float_conversion' },
                  { name: 'a',
                    type: 'integer', control_type: 'integer',
                    convert_output: 'integer_conversion' }
                ] },
              { name: 'oldHue',
                type: 'number', control_type: 'number',
                convert_output: 'float_conversion' },
              { name: 'source' }
            ] },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'colorMethod' }
            ] }
        ]
      when 'country'
        [
          { name: 'countryCode' },
          { name: 'countryName' },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings',
            type: 'object',
            properties: [] }
        ]
      when 'week'
        [
          { name: 'week', type: 'object',
            properties: [
              { name: 'startDate', type: 'date', control_type: 'date',
                convert_output: 'date_conversion' },
              { name: 'endDate', type: 'date', control_type: 'date',
                convert_output: 'date_conversion' }
            ] },
          { name: 'column_settings', type: 'object',
            properties: [] }
        ]
      when 'rating'
        [
          { name: 'rating',
            type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'symbol' },
              { name: 'limit',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' },
              { name: 'color' }
            ] }
        ]
      when 'phone'
        [
          { name: 'phone' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'show_flag',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' }
            ] }
        ]
      when 'timezone', 'world_clock'
        [
          { name: 'timezone' },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'format' },
              { name: 'startWorkingHours' },
              { name: 'endWorkingHours' },
              { name: 'show_utc_offset',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' }
            ] }
        ]
      when 'link'
        [
          { name: 'url' },
          { name: 'text' },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [] }
        ]
      when 'long-text', 'long_text'
        [
          { name: 'text' },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [] }
        ]
      when 'dependency'
        [
          { name: 'linkedPulseIds', type: 'array', of: 'object',
            properties: [
              { name: 'linkedPulseId',
                type: 'integer', control_type: 'integer',
                convert_output: 'integer_conversion' }
            ] },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'boardIds', label: 'Board IDs',
                type: 'array', of: 'integer' },
              { name: 'dependencyNewInfra',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' },
              { name: 'allowMultipleItems',
                type: 'boolean', control_type: 'checkbox',
                convert_output: 'boolean_conversion' }
            ] }
        ]
      when 'button'
        [
          { name: 'clicks',
            type: 'integer', control_type: 'integer',
            convert_output: 'integer_conversion' },
          { name: 'changed_at', type: 'date_time', control_type: 'date_time' },
          { name: 'column_settings', type: 'object',
            properties: [
              { name: 'buttonText' },
              { name: 'color' }
            ] }
        ]
      else
        []
      end
    end,
    format_output: lambda do |input|
      input&.map do |record|
        record['created_at'] = (record['created_at'].to_i / 100_000_00).
                               to_time.utc.iso8601
        record['data'] = parse_json(record['data'])
        record
      end
    end,
    index_by: lambda do |types, name|
      types&.each_with_object({}) do |item, hash|
        hash[item[name]] = item
      end
    end,
    get_metadata: lambda do |connection|
      payload = " query IntrospectionQuery {
          __schema {
            queryType { name }
            mutationType { name }
            subscriptionType { name }
            types {
              ...FullType
            }
            directives {
              name
              description
              locations
              args {
                ...InputValue
              }
            }
          }
        }

        fragment FullType on __Type {
          kind
          name
          description
          fields(includeDeprecated: true) {
            name
            description
            args {
              ...InputValue
            }
            type {
              ...TypeRef
            }
            isDeprecated
            deprecationReason
          }
          inputFields {
            ...InputValue
          }
          interfaces {
            ...TypeRef
          }
          enumValues(includeDeprecated: true) {
            name
            description
            isDeprecated
            deprecationReason
          }
          possibleTypes {
            ...TypeRef
          }
        }

        fragment InputValue on __InputValue {
          name
          description
          type { ...TypeRef }
          defaultValue
        }

        fragment TypeRef on __Type {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                    ofType {
                      kind
                      name
                      ofType {
                        kind
                        name
                      }
                    }
                  }
                }
              }
            }
          }
        }"
      post('https://api.monday.com/v2').payload(query: payload).
        headers(Authorization: connection['api_key'])
    end,
    generate_schema: lambda do |connection, input, verb, schema|
      action = input['object']
      types = call('get_metadata', connection)&.dig('data', '__schema', 'types')
      metadata = call('index_by', types, 'name')
      fields = metadata&.dig(verb, 'fields')&.detect do |item|
        item['name'] == action
      end
      if schema == 'input'
        args = fields&.dig('args')
        call('create_schema', input['fields_to_retrieve'], metadata, args, '', schema)
      elsif fields&.dig('type', 'kind') == 'LIST' || fields&.dig('type', 'ofType', 'kind') == 'LIST'        
        field = fields&.dig('type', 'ofType', 'name') || fields&.dig('type', 'ofType', 'ofType', 'name')        
        if fields&.[]('name') == 'boards' && schema == 'output'
          [
            { name: fields&.[]('name'),
              type: 'array', of: 'object',
              properties: call('create_schema', input['fields_to_retrieve'],
                               metadata, metadata&.dig(field, 'fields'), '', schema).concat([{ name: 'pos' }]) }
          ]
        else
          [
            { name: fields&.[]('name'),
              type: 'array', of: 'object',
              properties: call('create_schema', input['fields_to_retrieve'],
                               metadata, metadata&.dig(field, 'fields'), '', schema) }
          ]
        end
      else        
        field = fields&.dig('type', 'name') || fields&.dig('type', 'ofType', 'name') || fields&.dig('type', 'ofType', 'ofType', 'name')
        call('create_schema', input['fields_to_retrieve'],
             metadata, metadata&.dig(field, 'fields'), '', schema)
      end || []
    end,
    create_schema: lambda do |fields_to_retrieve, metadata, args, processed_objects, schema_type|
      var = if schema_type == 'output'
              selected_fields = []
              selected_fields = fields_to_retrieve.split(',') if fields_to_retrieve.present?
              (selected_fields&.each_with_object({}) do |selected_field, hash|
                field_names = selected_field&.split('~')&.first&.split('.')
                selected_field_name = field_names&.shift
                sub_fields = field_names&.join('.')
                hash[selected_field_name] = if hash[selected_field_name].present? &&
                                               sub_fields.present?
                                              "#{hash[selected_field_name] || ''}"\
                                              ",#{sub_fields}"
                                            elsif sub_fields.present?
                                              (hash[selected_field_name] || '') + sub_fields
                                            end
              end&.map do |selected_field_name, sub_fields|
                selected_arg = args&.find do |field|
                  if selected_field_name == 'items'
                    'items_page' == field['name'] || 'items' == field['name']
                  else
                    selected_field_name == field['name']
                  end
                end
                selected_arg['sub_fields'] = sub_fields if selected_arg.present?
                selected_arg
              end.presence || args)
            else
              args
            end
      var&.compact&.map do |schema|
        optional = schema&.dig('type', 'kind') != 'NON_NULL'
        field = {
          name: schema['name'],
          hint: schema['description'],
          optional: optional,
          sticky: true
        }
        type = if schema['type']['kind'] == 'NON_NULL'
                 schema['type']['ofType']['name']
               else
                 schema['type']['name'] || schema['type']['ofType']['name'] || schema['type']['ofType']['ofType']['name']
               end
        kind = if schema['type']['kind'] == 'NON_NULL'
          schema['type']['ofType']['kind'] || schema['type']['ofType']['ofType']['name']
               else
                 schema['type']['kind']
               end        
        next nil if selected_fields.blank? && %w[OBJECT LIST INTERFACE].include?(kind) && schema_type == 'output'
                
        case type
        when 'Boolean'
          field[:type] = :boolean
          field[:control_type] = :checkbox
          field[:convert_input] = :boolean_conversion
          field = field.deep_merge(
            {
              toggle_hint: 'Select from list',
              toggle_field: {
                name: schema['name'], label: schema['name'].labelize,
                hint: "#{schema['description']} Allowed values are <b>true</b>, <b>false</b>",
                optional: optional, sticky: true,
                type: :string,
                control_type: :text,
                convert_input: :boolean_conversion,
                toggle_hint: 'Use custom value'
              }
            }
          )
        when 'Float'
          field[:type] = :number
          field[:control_type] = :text
          field[:convert_input] = :float_conversion
        when 'Int'
          field[:type] = :integer
          field[:control_type] = :integer
          field[:convert_input] = :integer_conversion
        when 'Date', 'GraphQLDate'
          if %w[last_activity updated_at created_at].include?(schema['name'])
            field[:type] = :date_time
            field[:control_type] = :date_time
            field[:convert_input] = :date_time_conversion
            field[:convert_output] = 'format_date_time_utc'
          else
            field[:type] = :date
            field[:control_type] = :date
            field[:convert_input] = :date_conversion
          end
        when 'DateTime', 'ISO8601DateTime', 'GraphQLDateTime'
          field[:type] = :date_time
          field[:control_type] = :date_time
          field[:convert_input] = :date_time_conversion
          field[:convert_output] = 'format_date_time_utc'
        when 'JSON'
          if schema_type == 'output'
            field[:name] = schema['name'].to_s
          else
            field[:control_type] = 'schema-designer'
            field[:name] = "#{schema['name']}_schema_builder"
            field[:hint] = "#{schema['description']} Use Search boards "\
                           'action to retrieve the column values'
            field[:extends_schema] = true
          end
        else
          case kind
          when 'ENUM'
            field[:type] = 'String'
            field[:pick_list] = metadata&.dig(type, 'enumValues')&.map do |enum|
              [
                enum['name'].labelize, enum['name']
              ]
            end
            field = field.deep_merge(
              {
                type: :string,
                control_type: :select,
                toggle_hint: 'Select from list',
                toggle_field: {
                  name: schema['name'], label: schema['name'].labelize,
                  hint: schema['description'],
                  optional: optional, sticky: true,
                  type: :string,
                  control_type: :text,
                  toggle_hint: 'Use custom value'
                }
              }
            )
          when 'LIST'
            of_type = if schema['type']['kind'] == 'NON_NULL' || schema.dig('type', 'ofType', 'kind') == 'NON_NULL'
              schema.dig('type', 'ofType', 'ofType', 'ofType', 'name') || schema.dig('type', 'ofType', 'ofType', 'name')
                      else
                        schema.dig('type', 'ofType', 'name') || schema.dig('type', 'ofType', 'ofType', 'ofType' 'name')
                      end
            list_kind = if schema['type']['kind'] == 'NON_NULL' && schema.dig('type', 'ofType', 'ofType', 'kind') == 'NON_NULL'
                          schema.dig('type', 'ofType', 'ofType', 'ofType', 'kind')
                        elsif schema['type']['kind'] == 'NON_NULL' || schema.dig('type', 'ofType', 'kind') == 'NON_NULL'
                          schema.dig('type', 'ofType', 'ofType', 'kind')
                        else
                          schema.dig('type', 'ofType', 'kind') || schema.dig('type', 'ofType', 'ofType', 'ofType', 'kind')
                        end
            of = case of_type
                 when 'Boolean'
                   'boolean'
                 when 'Float'
                   'number'
                 when 'Int', 'ID'
                   'integer'
                 when 'Date', 'GraphQLDate'
                   'date'
                 when 'DateTime', 'ISO8601DateTime', 'GraphQLDateTime'
                   'date_time'
                 else
                   if %w[OBJECT INPUT_OBJECT INTERFACE].include?(list_kind)
                     'object'
                   else
                     'string'
                   end
                 end            
            object_fields = if %w[OBJECT INTERFACE].include?(list_kind)
                              metadata.dig(of_type, 'fields')
                            else
                              metadata.dig(of_type, 'inputFields')
                            end
            field[:type] = 'array'
            field[:of] = of
            field[:properties] = if processed_objects&.split('.')&.include?(of_type)
                                   []
                                 elsif schema['name'] == 'column_values' && schema_type == 'output'
                                   call('create_schema', schema['sub_fields'],
                                        metadata, object_fields,
                                        "#{processed_objects}.#{of_type}", schema_type).concat(
                                          [
                                            { name: 'title', hint: "The column's title.", optional: false, sticky: true, type: :string,
                                              control_type: :text },
                                            { name: 'additional_info', hint: "The column value's additional information.",
                                              optional: true, sticky: true },
                                            { name: 'description', hint: "The column's description.", optional: true, sticky: true,
                                              type: :string, control_type: :text }
                                          ]
                                        )
                                 elsif (schema['name'] == 'columns' || schema['name'] == 'board') && schema_type == 'output'
                                   call('create_schema', schema['sub_fields'],
                                        metadata, object_fields,
                                        "#{processed_objects}.#{of_type}", schema_type).concat(
                                          [
                                            { name: 'pos' }
                                          ]
                                        )
                                 else
                                   # processed_objects.push(ofType)
                                   call('create_schema', schema['sub_fields'],
                                        metadata, object_fields,
                                        "#{processed_objects}.#{of_type}", schema_type)
                                 end
          when 'OBJECT', 'INTERFACE', 'INPUT_OBJECT'
            if schema['name'] == 'items_page'
              field[:type] = 'array'
              field[:of] = 'object'
              field[:name] = 'items'
            else
              field[:type] = 'object'
            end
            metadata_fields = if type == 'INPUT_OBJECT'
                                metadata.dig(type, 'inputFields')
                              else
                                metadata.dig(type, 'fields')
                              end
            field[:properties] = if processed_objects&.split('.')&.include?(type)
                                   []
                                 elsif schema['name'] == 'items_page'
                                   schema['sub_fields'] = if schema['sub_fields'].blank?
                                                            'items'
                                                          else
                                                            "items.#{schema['sub_fields'].split(',').join(',items.')}"
                                                          end
                                   call('create_schema', schema['sub_fields'],
                                        metadata, metadata_fields,
                                        "#{processed_objects}.#{type}", schema_type).find { |e| e[:name] == 'items' }&.[](:properties)
                                 elsif schema['name'] == 'boards' || schema['name'] == 'board'
                                   call('create_schema', schema['sub_fields'],
                                        metadata, metadata_fields,
                                        "#{processed_objects}.#{type}", schema_type).concat([
                                                                                              { name: 'pos' }
                                                                                            ])
                                 else
                                   # processed_objects.push(type)
                                   call('create_schema', schema['sub_fields'],
                                        metadata, metadata_fields,
                                        "#{processed_objects}.#{type}", schema_type)
                                 end
          else
            field = field.merge(
              {
                type: :string,
                control_type: :text
              }
            )
          end
        end

        field
      end&.compact
    end,
    get_all_fields: lambda do |input|
      case call('get_recipe_api_version', input)
      when '2023-07'
        input['fields_to_retrieve'] = input['fields_to_retrieve'].gsub(/\bitems(?:)?\b/, 'items_page.items').
                                      gsub('items_page.items~', 'items_page.cursor~String').
                                      gsub('column_values.additional_info', 'column_values.column').
                                      gsub('column_values.title', 'column_values.column.title').
                                      gsub('column_values.description', 'column_values.column.description')
      when '2023-10'
        input['fields_to_retrieve'] = input['fields_to_retrieve']
      else
        error('Unhandled recipe API version')
      end
      obj = input['fields_to_retrieve']&.split(',')&.each_with_object({}) do |item, hash|
        hash[item.split('~').first] = {}
      end
      test_item = (obj.map do |main_key, main_value|
                     main_key.to_s.split('.').reverse.inject(main_value) do |value, key|
                       { key => value }
                     end
                   end).inject({}) do |item, hash|
        hash = hash.deep_merge(item)
        hash
      end
      test_item.to_json.gsub(':{}', ' ').gsub('{', ' { ').gsub('}', '} ').delete('":,')
    end,
    get_root_fields: lambda do |object, eos|
      eos.map do |field|
        if field['name'] == object
          call('get_root_fields', object, field['properties'])
        else
          field['name'] unless field['properties'].present?
        end
      end&.concat
    end,
    format_input: lambda do |input, eis|
      select_field = parse_json(eis.to_json).select do |item|
        item['control_type'] == 'select'
      end&.pluck('name')
      input.except('object', 'fields_to_retrieve',
                   'workato_clear_column').map do |key, value|
        next nil if key.include?('_schema_builder') || value.nil?

        "#{key}:" + if select_field.include?(key)
                      value.to_s
                    elsif value.is_a?(Hash)
                      field_name = key if %w[create_item create_subitem
                                             change_multiple_column_values].include? input['object']
                      if input['workato_clear_column'] == true
                        call('format_params_update', field_name, value).to_json.to_json
                      else
                        call('format_params', field_name, value).to_json.to_json
                      end
                    else
                      value.to_json
                    end&.gsub(/\\\\u003e|\\u003e/, '>')&.
                    gsub(/\\\\u003c|\\u003c/, '<')&.
                    gsub(/\\\\u0026|\\u0026/, '&')
      end.compact.join(', ')
    end,
    format_params_update: lambda do |field_name, input|
      if input.is_a?(Array)
        input.map do |item|
          call('format_params_update', field_name, item).presence
        end
      elsif input.is_a?(Hash)
        input.each_with_object({}) do |(key, value), hash|
          if key.to_s == 'personsAndTeams'
            val = value&.map do |v|
              if (v.present? && v.keys.include?('id') && v.keys.include?('kind')) && ((v['id'].blank? || v['id'] == '""' || v['id'] == "''") && (v['kind'].blank? || v['kind'] == '""' || v['kind'] == "''"))
                nil
              elsif v.present? && v['id'].present? && v['kind'].present?
                call('format_params', field_name, v).presence
              else
                v
              end
            end&.compact
            hash[key] = val
          elsif value.is_a?(Array)
            val = call('format_params_update', field_name, value)
            hash[key] = val if val.present?
          elsif value.is_a?(Hash)
            column_values = value.values || []
            if field_name == 'column_values' && (column_values.include?(nil) || column_values.include?('') || column_values.include?("''") || column_values.include?('""'))
              hash[key] = null
            else
              val = call('format_params_update', field_name, value)
              hash[key] = val if val.present?
            end
          else
            hash[key] = if value.blank? || value == '""' || value == "''"
                          nil
                        else
                          value
                        end
          end
        end
      else
        input
      end
    end,
    format_params: lambda do |field_name, input|
      if input.is_a?(Array)
        input.map do |item|
          call('format_params', field_name, item).presence
        end&.compact
      elsif input.is_a?(Hash)
        input.each_with_object({}) do |(key, value), hash|
          if key.to_s == 'personsAndTeams'
            val = value&.map do |v|
              if v.present? && v['id'].present? && v['kind'].present?
                call('format_params', field_name, v).presence
              end
            end&.compact
            hash[key] = val if val.present?
          elsif value.is_a?(Array)
            val = call('format_params', field_name, value)&.compact
            hash[key] = val if val.present?
          elsif value.is_a?(Hash)
            column_values = value.values || []
            next if field_name == 'column_values' &&
                    (column_values.include?(nil) || column_values.include?(''))

            val = call('format_params', field_name, value)&.compact
            hash[key] = val if val.present?
          elsif value.present?
            hash[key] = value
          end
        end&.compact
      elsif input.present?
        input
      end
    end,
    format_response: lambda do |response, input|
      case call('get_recipe_api_version', input)
      when '2023-07', '2023-10'
        if response.is_a?(Array)
          response.map do |array_value|
            call('format_response', array_value, input)
          end
        elsif response.is_a?(Hash)
          response.each_with_object({}) do |(key, value), hash|
            if key.to_s == 'items_page'
              hash['items'] = call('format_response', value.delete('items'), input)
            elsif key.to_s == 'column_values'
              val = value&.map do |c_v|
                if c_v&.[]('column')&.keys&.include?('title')
                  c_v['title'] =
                    c_v&.[]('column')&.delete('title')
                end
                if c_v&.[]('column')&.keys&.include?('description')
                  c_v['description'] =
                    c_v&.[]('column')&.delete('description')
                end
                c_v.delete('column') if c_v&.[]('column')&.blank?
                c_v
              end
              hash[key] = call('format_response', val, input)
            elsif value.is_a?(Array) || value.is_a?(Hash)
              hash[key] = call('format_response', value, input)
            else
              value = call('format_type_response', value) if key.to_s == 'type'
              hash[key] = value
            end
          end
        else
          response
        end
      else
        error('Unhandled recipe API version')
      end
    end,
    format_type_response: lambda do |value|
                            case value
                            when 'auto_number'
                              'autonumber'
                            when 'people'
                              'multiple-person'
                            when 'status'
                              'color'
                            when 'numbers'
                              'numeric'
                            when 'timeline'
                              'timerange'
                            when 'long_text'
                              'long-text'
                            when 'board_relation'
                              'board-relation'
                            when 'mirror'
                              'lookup'
                            when 'checkbox'
                              'boolean'
                            when 'world_clock'
                              'timezone'
                            when 'item_id'
                              'pulse-id'
                            when 'tags'
                              'tag'
                            when 'vote'
                              'votes'
                            when 'creation_log'
                              'pulse-log'
                            when 'last_updated'
                              'pulse-updated'
                            when 'progress'
                              'columns-battery'
                            when 'color_picker'
                              'color-picker'
                            when 'time_tracking'
                              'duration'
                            else
                              value
                            end
                          end,
    format_get_items_page_by_column_values: lambda do |input|
      input[:object] = 'items_page_by_column_values'
      input
    end,
    get_recipe_api_version: lambda do |input|
      if input['recipe_api_version'] == '2023-07' || input['recipe_api_version'].blank?
        '2023-07'
      else
        input['recipe_api_version']
      end
    end,
    format_output_fields: lambda do |input, output_fields|
      output_fields = case call('get_recipe_api_version', input)
                      when '2023-07'
                        output_fields.gsub(/\bpos\b/, 'id')
                      when '2023-10'
                        output_fields
                      else
                        error('Unhandled recipe API version')
                      end
    end,
    format_date_time_utc: lambda do |value|
      value.to_time.utc.iso8601
    end
  },

  pick_lists: {
    search_object_list: lambda do |_connection|
      %w[users items boards updates].map { |e| [e.labelize, e] }
    end,
    get_object_list: lambda do |_connection|
      [
        %w[Item items],
        %w[Item\ by\ column\ values items_by_column_values]
      ]
    end,
    create_object_list: lambda do |_connection|
      [
        %w[Item create_item],
        %w[Subitem create_subitem],
        %w[Update create_update],
        %w[Notification create_notification]
      ]
    end,
    update_object_list: lambda do
      [
        %w[Item change_multiple_column_values]
      ]
    end,
    upload_object_list: lambda do
      [
        ['File to update', 'add_file_to_update'],
        ['File to column', 'add_file_to_column']
      ]
    end,
    move_object_list: lambda do
      [
        %w[Item\ to\ group move_item_to_group],
        %w[Item\ to\ board move_item_to_board]
      ]
    end,
    archive_object_list: lambda do
      [
        %w[Item archive_item]
      ]
    end,
    delete_object_list: lambda do
      [
        %w[Item delete_item]
      ]
    end,

    mutate_fields_list: lambda do |connection, **args|
      types = call('get_metadata', connection)&.dig('data', '__schema', 'types')
      metadata = call('index_by', types, 'name')
      if args&.[](:__parent_id).present?
        object_name = (args&.[](:__parent_id)&.split('~')&.last).split('.').last
        object_name = object_name.singularize unless object_name == 'WorkspaceSettings'
        # object_name = (object_name.singularize.labelize).split(' ').map { |i| i.capitalize }.join('')
        object_name = (object_name.labelize).split(' ').map { |i| i.capitalize }.join('')
        list = metadata&.dig(object_name, 'fields')&.map do |schema|
          kind = if %w[LIST NON_NULL].include?(schema['type']['kind'])
                   if %w[NON_NULL].include?(schema['type']['ofType']['kind'])
                     if %w[NON_NULL].include?(schema['type']['ofType']['ofType']['kind'])
                       schema['type']['ofType']['ofType']['ofType']['kind']
                     else
                       schema['type']['ofType']['ofType']['kind']
                     end
                   else
                     schema['type']['ofType']['kind']
                   end
                 else
                   schema['type']['kind']
                 end
          int_object_name = if %w[LIST NON_NULL].include?(schema['type']['kind'])
                              if %w[LIST NON_NULL].include?(schema['type']['ofType']['kind'])
                                schema['type']['ofType']['ofType']['name'] || schema['type']['ofType']['ofType']['ofType']['name']
                              else
                                schema['type']['ofType']['name']
                              end
                            else
                              schema['type']['name']
                            end
          if schema['name'] == 'items_page'
            schema['name'] = 'items'
            kind = 'LIST'
            int_object_name = 'Item'
          end
          flag = ((args&.[](:__parent_id)&.split('~')&.last).split('.').select do |obj|
            obj == object_name
          end || []).count <= 1 &&
                 ((args&.[](:__parent_id)&.split('~')&.first).split('.').select do |obj|
                   obj == schema['name']
                 end || []).count <= 1
          if flag && !(args&.[](:__parent_id)&.split('~')&.last).
             split('.').include?(int_object_name)

            case call('get_recipe_api_version', 'recipe_api_version' => args[:recipe_api_version])
            when '2023-07', '2023-10'
              parent = args&.[](:__parent_id)&.split('~')&.last&.split('.')&.last

              if (%w[Account AccountProduct Product Document Folder Tag Team User
                     Workspace].include?(parent) && schema['name'] == 'id') ||
                 (parent == 'Board' && %w[board_folder_id workspace_id].include?(schema['name'])) ||
                 (parent == 'Document' && %w[object_id workspace_id
                                             doc_folder_id].include?(schema['name'])) ||
                 (parent == 'DocumentBlock' && %w[doc_id].include?(schema['name'])) ||
                 (parent == 'Folder' && %w[owner_id].include?(schema['name'])) ||
                 (parent == 'Webhook' && %w[board_id].include?(schema['name']))
                int_object_name = 'Int'
              elsif schema['name'] == 'type' && int_object_name == 'ColumnType'
                int_object_name = 'String'
              end
            else
              error('Unhandled recipe API version')
            end
            next if args&.[](:__parent_id)&.split('~')&.first.include?('column_values.column') && %w[
              title description
            ].include?(schema['name'])

            [schema['name'].labelize, [[args&.[](:__parent_id)&.split('~')&.first,
                                        schema['name']].join('.'),
                                       [args&.[](:__parent_id)&.split('~')&.last,
                                        int_object_name].join('.')].join('~'),
             nil, flag && %w[OBJECT LIST INTERFACE].include?(kind)]
          end
        end&.compact
        if args&.[](:__parent_id)&.split('~')&.first&.split('.')&.last == 'column_values'
          schemas = [
            { 'name' => 'title', 'type' => 'String', 'flag' => false },
            { 'name' => 'additional_info', 'type' => 'JSON', 'flag' => false },
            { 'name' => 'description', 'type' => 'String', 'flag' => false }
          ]
          list.concat(
            schemas.map do |schema|
              [schema['name'].labelize,
               [[args&.[](:__parent_id)&.split('~')&.first, schema['name']].join('.'),
                [args&.[](:__parent_id)&.split('~')&.last, schema['type']].join('.')].join('~'),
               nil, schema['flag']]
            end
          )
        elsif args&.[](:__parent_id)&.split('~')&.first&.split('.')&.last == 'board' ||
              args&.[](:__parent_id)&.split('~')&.first&.split('.')&.last == 'columns'
          schemas = [
            { 'name' => 'pos', 'type' => 'String', 'flag' => false }
          ]
          list.concat(
            schemas.map do |schema|
              [schema['name'].labelize,
               [[args&.[](:__parent_id)&.split('~')&.first, schema['name']].join('.'),
                [args&.[](:__parent_id)&.split('~')&.last, schema['type']].join('.')].join('~'),
               nil, schema['flag']]
            end
          )
        end
        list
      else
        fields = metadata&.dig('Mutation', 'fields')&.detect do |item|
          item['name'] == args[:object]
        end
        field = if fields&.dig('type', 'kind') == 'LIST'
                  if %w[LIST NON_NULL].include?(fields['type']['ofType']['kind'])
                    fields['type']['ofType']['ofType']['name'] || fields['type']['ofType']['ofType']['ofType']['name']
                  else
                    fields['type']['ofType']['name']
                  end
                else
                  fields&.dig('type', 'name') || fields&.dig('type', 'ofType', 'name')
                end
        list = metadata&.dig(field, 'fields')&.map do |schema|
          kind = if %w[LIST NON_NULL].include?(schema['type']['kind'])                    
                   if %w[NON_NULL].include?(schema['type']['ofType']['kind'])
                     if %w[NON_NULL].include?(schema['type']['ofType']['ofType']['kind'])
                       schema['type']['ofType']['ofType']['ofType']['kind']
                     else
                       schema['type']['ofType']['ofType']['kind']
                     end
                   else
                     schema['type']['ofType']['kind']
                   end                                    
                 else
                   schema['type']['kind']
                 end
          object_name = if %w[LIST NON_NULL].include?(schema['type']['kind'])
                          if %w[LIST NON_NULL].include?(schema['type']['ofType']['kind'])
                            schema['type']['ofType']['ofType']['name'] || schema['type']['ofType']['ofType']['ofType']['name']
                          else
                            schema['type']['ofType']['name']
                          end
                        else
                          schema['type']['name']
                        end
          if schema['name'] == 'items_page'
            schema['name'] = 'items'
            kind = 'LIST'
            object_name = 'Item'
          end

          case call('get_recipe_api_version', 'recipe_api_version' => args[:recipe_api_version])
          when '2023-07', '2023-10'
            parent = args&.[](:object)

            if (parent == 'boards' && %w[board_folder_id workspace_id].include?(schema['name'])) ||
               (parent == 'users' && %w[id].include?(schema['name']))
              object_name = 'Int'
            elsif schema['name'] == 'type' && object_name == 'ColumnType'
              object_name = 'String'
            end
          else
            error('Unhandled recipe API version')
          end

          [schema['name'].labelize, [schema['name'], object_name].join('~'), nil,
           %w[OBJECT LIST INTERFACE].include?(kind)]
        end
        if args&.[](:object) == 'boards' || args&.[](:object) == 'columns'
          list = list.concat(
            [
              ['Pos', 'pos~String', nil, false]
            ]
          )
        end
        list
      end
    end,
    query_fields_list: lambda do |connection, **args|
      case call('get_recipe_api_version', 'recipe_api_version' => args[:recipe_api_version])
      when '2023-07'
        if args[:object] == 'items_by_column_values'
          call('format_get_items_page_by_column_values',
               args)
        end
      else
        error('Unhandled recipe API version')
      end
      types = call('get_metadata', connection)&.dig('data', '__schema', 'types')
      metadata = call('index_by', types, 'name')
      if args&.[](:__parent_id).present?
        object_name = (args&.[](:__parent_id)&.split('~')&.last).split('.').last
        object_name = object_name.singularize unless object_name == 'WorkspaceSettings'
        # object_name = (object_name.singularize.labelize).split(' ').map { |i| i.capitalize }.join('')
        object_name = (object_name.labelize).split(' ').map { |i| i.capitalize }.join('')
        list = metadata&.dig(object_name, 'fields')&.map do |schema|
          kind = if %w[LIST NON_NULL].include?(schema['type']['kind'])
                   if %w[NON_NULL].include?(schema['type']['ofType']['kind'])
                     if %w[NON_NULL].include?(schema['type']['ofType']['ofType']['kind'])
                       schema['type']['ofType']['ofType']['ofType']['kind']
                     else
                       schema['type']['ofType']['ofType']['kind']
                     end
                   else
                     schema['type']['ofType']['kind']
                   end   
                  else
                    schema['type']['kind']
                  end
          int_object_name = if %w[LIST NON_NULL].include?(schema['type']['kind'])
                              if %w[LIST NON_NULL].include?(schema['type']['ofType']['kind'])
                                schema['type']['ofType']['ofType']['name'] || schema['type']['ofType']['ofType']['ofType']['name']
                              else
                                schema['type']['ofType']['name']
                              end
                            else
                              schema['type']['name']
                            end
          if schema['name'] == 'items_page'
            schema['name'] = 'items'
            kind = 'LIST'
            int_object_name = 'Item'
          end
          flag = ((args&.[](:__parent_id)&.split('~')&.last).split('.').select do |obj|
            obj == object_name
          end || []).count <= 1 &&
                 ((args&.[](:__parent_id)&.split('~')&.first).split('.').select do |obj|
                   obj == schema['name']
                 end || []).count <= 1
          if flag && !(args&.[](:__parent_id)&.
             split('~')&.last).split('.').include?(int_object_name)

            case call('get_recipe_api_version', 'recipe_api_version' => args[:recipe_api_version])
            when '2023-07'
              parent = args&.[](:__parent_id)&.split('~')&.last&.split('.')&.last

              if (%w[Account AccountProduct Product Document Folder Tag Team User
                     Workspace].include?(parent) && schema['name'] == 'id') ||
                 (parent == 'Board' && %w[board_folder_id workspace_id].include?(schema['name'])) ||
                 (parent == 'Document' && %w[object_id workspace_id
                                             doc_folder_id].include?(schema['name'])) ||
                 (parent == 'DocumentBlock' && %w[doc_id].include?(schema['name'])) ||
                 (parent == 'Folder' && %w[owner_id].include?(schema['name'])) ||
                 (parent == 'Webhook' && %w[board_id].include?(schema['name']))
                int_object_name = 'Int'
              elsif schema['name'] == 'type' && int_object_name == 'ColumnType'
                int_object_name = 'String'
              end
            else
              error('Unhandled recipe API version')
            end
            next if args&.[](:__parent_id)&.split('~')&.first.include?('column_values.column') && %w[
              title description
            ].include?(schema['name'])

            [schema['name'].labelize,
             [[args&.[](:__parent_id)&.split('~')&.first, schema['name']].join('.'),
              [args&.[](:__parent_id)&.split('~')&.last, int_object_name].join('.')].join('~'),
             nil, flag && %w[OBJECT LIST INTERFACE].include?(kind)]
          end
        end&.compact
        if args&.[](:__parent_id)&.split('~')&.first&.split('.')&.last == 'column_values'
          schemas = [
            { 'name' => 'title', 'type' => 'String', 'flag' => false },
            { 'name' => 'additional_info', 'type' => 'JSON', 'flag' => false },
            { 'name' => 'description', 'type' => 'String', 'flag' => false }
          ]
          list.concat(
            schemas.map do |schema|
              [schema['name'].labelize,
               [[args&.[](:__parent_id)&.split('~')&.first, schema['name']].join('.'),
                [args&.[](:__parent_id)&.split('~')&.last, schema['type']].join('.')].join('~'),
               nil, schema['flag']]
            end
          )
        elsif args&.[](:__parent_id)&.split('~')&.first&.split('.')&.last == 'board' ||
              args&.[](:__parent_id)&.split('~')&.first&.split('.')&.last == 'columns'
          schemas = [
            { 'name' => 'pos', 'type' => 'String', 'flag' => false }
          ]
          list.concat(
            schemas.map do |schema|
              [schema['name'].labelize,
               [[args&.[](:__parent_id)&.split('~')&.first, schema['name']].join('.'),
                [args&.[](:__parent_id)&.split('~')&.last, schema['type']].join('.')].join('~'),
               nil, schema['flag']]
            end
          )
        end
        list
      else
        args[:object] = 'items' if args[:object] == 'items_page_by_column_values'
        fields = metadata&.dig('Query', 'fields')&.detect do |item|
          item['name'] == args[:object]
        end
        field = if fields&.dig('type', 'kind') == 'LIST'
                  if %w[LIST NON_NULL].include?(fields['type']['ofType']['kind'])
                    fields['type']['ofType']['ofType']['name'] || fields['type']['ofType']['ofType']['ofType']['name']
                  else
                    fields['type']['ofType']['name']
                  end
                else
                  fields&.dig('type', 'name') || fields&.dig('type', 'ofType', 'name')
                end
        list = metadata&.dig(field, 'fields')&.map do |schema|
          kind = if %w[LIST NON_NULL].include?(schema['type']['kind'])                    
                   if %w[NON_NULL].include?(schema['type']['ofType']['kind'])
                     if %w[NON_NULL].include?(schema['type']['ofType']['ofType']['kind'])
                       schema['type']['ofType']['ofType']['ofType']['kind']
                     else
                       schema['type']['ofType']['ofType']['kind']
                     end
                   else
                     schema['type']['ofType']['kind']
                   end                                    
                 else
                   schema['type']['kind']
                 end
          object_name = if %w[LIST NON_NULL].include?(schema['type']['kind'])
                          if %w[LIST NON_NULL].include?(schema['type']['ofType']['kind'])
                            schema['type']['ofType']['ofType']['name'] || schema['type']['ofType']['ofType']['ofType']['name']
                          else
                            schema['type']['ofType']['name']
                          end
                        else
                          schema['type']['name']
                        end
          if schema['name'] == 'items_page'
            schema['name'] = 'items'
            kind = 'LIST'
            object_name = 'Item'
          end
          case call('get_recipe_api_version', 'recipe_api_version' => args[:recipe_api_version])
          when '2023-07'
            parent = args&.[](:object)

            if (parent == 'boards' && %w[board_folder_id workspace_id].include?(schema['name'])) ||
               (parent == 'users' && %w[id].include?(schema['name']))
              object_name = 'Int'
            elsif schema['name'] == 'type' && object_name == 'ColumnType'
              object_name = 'String'
            end
          else
            error('Unhandled recipe API version')
          end
          [schema['name'].labelize,
           [schema['name'], object_name].join('~'), nil, %w[OBJECT LIST INTERFACE].include?(kind)]
        end
        if args&.[](:object) == 'boards' || args&.[](:object) == 'columns'
          list = list.concat(
            [
              ['Pos', 'pos~String', nil, false]
            ]
          )
        end
        list
      end
    end,
    column_value_list: lambda do |_connection, board_id:|
      payload = {
        query: "query {boards(ids: #{board_id.to_i}){columns{id,type,title,settings_str}}}"
      }
      response = post('', payload).after_response do |_code, body, _headers|
        if body['errors'].present?
          error(body.dig('errors', 0, 'message'))
        elsif body['error_code'].present? || body['error_message'].present?
          error(body['error_message'])
        elsif body&.dig('data', 'boards').blank?
          error('The board does not exist. Please check your board ID and try again')
        else
          body
        end
      end
      response.after_error_response(/.*/) do |_code, body, _header, message|
        error("#{message}: #{body}")
      end&.
        dig('data', 'boards', 0, 'columns')&.
        map { |e| [e['title'].labelize, e['id']] }
    end,
    column_list: lambda do |_connection, board_id:|
      payload = {
        query: "query { boards (ids: #{board_id.to_i}) { columns { title id } } }"
      }
      post('', payload)&.
        dig('data', 'boards', 0, 'columns')&.
        map { |e| [e['title'].labelize, e['id']] }
    end,
    column_list_with_type: lambda do |_connection, board_id:|
      payload = {
        query: "query { boards (ids: #{board_id.to_i}) { columns { title id type} } }"
      }
      post('', payload)&.
      dig('data', 'boards', 0, 'columns')&.
      map do |e|
        next if %w[ name duration votes autonumber lookup
                    pulse-updated pulse-log color-picker
                    formula pulse-id columns-battery
                    button subtasks ].include?(e['type'])

        [e['title'].labelize, e['id']]
      end&.compact
    end,
    group_list: lambda do |_connection, board_id:|
      payload = { query: "query { boards (ids: #{board_id.to_i}) { groups { title id } } }" }
      post('', payload)&.
        dig('data', 'boards', 0, 'groups')&.
        map { |e| [e['title'].labelize, e['id']] }
    end,
    board_list: lambda do
      payload = { query: 'query { boards { name id } }' }
      post('', payload)&.
        dig('data', 'boards')&.map { |e| [e['name'].labelize, e['id'].to_s] }
    end,
    country_codes: lambda do
      get('http://country.io/names.json').keys.map { |k| [k, k] }
    end,
    country_names: lambda do |countrycode:|
      get('http://country.io/names.json').each_with_object({}) do |(k, v), a|
        a[k] = [[v, v]]
      end[countrycode] || []
    end,
    boards: lambda do |_connection|
      post('https://api.monday.com/v2',
           query: '{boards(limit:1000){id,name}}')['data']['boards'].
        map { |board| [board['name'], board['id']] }
    end,
    time_zone: lambda do
      get('https://raw.githubusercontent.com/eggert/tz/master/zone1970.tab').
        response_format_raw.gsub(/(#(.?|.+)\n)|(^.+?\t.+?\t)|(\t.+)/, '').
        gsub(/\n/, ',').split(',').map { |v| [v, v] }
    end
  }
}