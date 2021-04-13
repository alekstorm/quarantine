# typed: strict

begin
  require 'google_drive'
rescue LoadError
end
require 'quarantine/databases/base'

class Quarantine
  module Databases
    class GoogleSheets < Base
      extend T::Sig

      sig { params(options: T::Hash[T.untyped, T.untyped]).void }
      def initialize(options)
        super()

        @options = options
      end

      sig { override.params(table_name: String).returns(T::Enumerable[Item]) }
      def fetch_items(table_name)
        parse_rows(spreadsheet.worksheet_by_title(table_name))
      end

      sig do
        override.params(
          table_name: String,
          items: T::Array[Item]
        ).void
      end
      def write_items(table_name, items)
        worksheet = spreadsheet.worksheet_by_title(table_name)
        headers = worksheet.rows.first
        new_rows = []

        # Map existing ID to row index
        indexes = Hash[parse_rows(worksheet).each_with_index.map { |item, idx| [item['id'], idx] }]

        items.each do |item|
          cells = headers.map { |header| item[header].to_s }
          row_idx = indexes[item['id']]
          if row_idx
            # Overwrite existing row
            headers.each_with_index do |_header, col_idx|
              worksheet[row_idx + 2, col_idx + 1] = cells[col_idx]
            end
          else
            new_rows << cells
          end
        end

        # Insert any items whose IDs weren't found in existing rows at the end
        worksheet.insert_rows(worksheet.rows.count + 1, new_rows)
        worksheet.save
      end

      private

      sig { returns(GoogleDrive::Session) }
      def session
        @session = T.let(@session, T.nilable(GoogleDrive::Session))
        @session ||= begin
          authorization = @options[:authorization]
          case authorization[:type]
          when :service_account_key
            GoogleDrive::Session.from_service_account_key(authorization[:file])
          when :config
            GoogleDrive::Session.from_config(authorization[:file])
          else
            raise "Invalid authorization type: #{authorization[:type]}"
          end
        end
      end

      sig { returns(GoogleDrive::Spreadsheet) }
      def spreadsheet
        @spreadsheet = T.let(@spreadsheet, T.nilable(GoogleDrive::Spreadsheet))
        @spreadsheet ||= begin
          spreadsheet = @options[:spreadsheet]
          case spreadsheet[:type]
          when :by_key
            session.spreadsheet_by_key(spreadsheet[:key])
          when :by_title
            session.spreadsheet_by_title(spreadsheet[:title])
          when :by_url
            session.spreadsheet_by_url(spreadsheet[:url])
          else
            raise "Invalid spreadsheet type: #{spreadsheet[:type]}"
          end
        end
      end

      sig { params(worksheet: GoogleDrive::Worksheet).returns(T::Enumerable[Item]) }
      def parse_rows(worksheet)
        headers, *rows = worksheet.rows

        rows.map do |row|
          hash_row = Hash[headers.zip(row)]
          # TODO: use Google Sheets developer metadata to store type information
          hash_row['extra_attributes'] = JSON.parse(hash_row['extra_attributes']) if hash_row['extra_attributes']
          hash_row
        end
      end
    end
  end
end
