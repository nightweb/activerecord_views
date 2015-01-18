require 'spec_helper'

describe ActiveRecordViews::ChecksumCache do
  let(:connection) { ActiveRecord::Base.connection }

  describe 'initialisation' do
    context 'no existing table' do
      it 'creates the table' do
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ACREATE TABLE active_record_views/).once.and_call_original

        expect(connection.table_exists?('active_record_views')).to eq false
        ActiveRecordViews::ChecksumCache.new(connection)
        expect(connection.table_exists?('active_record_views')).to eq true

        expect(connection.column_exists?('active_record_views', 'class_name')).to eq true
        expect(connection.column_exists?('active_record_views', 'options')).to eq true
      end
    end

    context 'existing table with current structure' do
      before do
        ActiveRecordViews::ChecksumCache.new(connection)
        expect(connection.table_exists?('active_record_views')).to eq true
      end

      it 'does not recreate the table' do
        expect(ActiveRecord::Base.connection).to receive(:execute).never

        ActiveRecordViews::ChecksumCache.new(connection)
      end
    end

    context 'existing table without class name' do
      before do
        connection.execute 'CREATE TABLE active_record_views(name text PRIMARY KEY, checksum text NOT NULL);'

        connection.execute 'CREATE VIEW test_view AS SELECT 42 AS id;'
        connection.execute "INSERT INTO active_record_views VALUES ('test_view', 'dummy');"

        connection.execute 'CREATE VIEW other_view AS SELECT 123 AS id;'
      end

      it 'drops existing managed views recreates the table' do
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ABEGIN\z/).once.and_call_original
        if Rails::VERSION::MAJOR < 4
          expect(ActiveRecord::Base.connection).to receive(:execute).with('SELECT name FROM active_record_views;', nil).once.and_call_original
        end
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ADROP VIEW IF EXISTS test_view CASCADE;\z/).once.and_call_original
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ADROP TABLE active_record_views;\z/).once.and_call_original
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ACREATE TABLE active_record_views/).once.and_call_original
        expect(ActiveRecord::Base.connection).to receive(:execute).with(/\ACOMMIT\z/).once.and_call_original

        expect(connection.column_exists?('active_record_views', 'class_name')).to eq false
        expect(ActiveRecordViews.view_exists?(connection, 'test_view')).to eq true
        expect(ActiveRecordViews.view_exists?(connection, 'other_view')).to eq true

        ActiveRecordViews::ChecksumCache.new(connection)

        expect(connection.column_exists?('active_record_views', 'class_name')).to eq true
        expect(ActiveRecordViews.view_exists?(connection, 'test_view')).to eq false
        expect(ActiveRecordViews.view_exists?(connection, 'other_view')).to eq true
      end
    end

    context 'existing table without options' do
      before do
        connection.execute 'CREATE TABLE active_record_views(name text PRIMARY KEY, class_name text NOT NULL UNIQUE, checksum text NOT NULL);'

        connection.execute 'CREATE VIEW test_view AS SELECT 42 AS id;'
        connection.execute "INSERT INTO active_record_views VALUES ('test_view', 'dummy', 'Dummy');"
      end

      it 'upgrades the table without losing data' do
        expect(ActiveRecord::Base.connection).to receive(:execute).with("ALTER TABLE active_record_views ADD COLUMN options json NOT NULL DEFAULT '{}';").once.and_call_original

        expect(connection.column_exists?('active_record_views', 'options')).to eq false
        expect(ActiveRecordViews.view_exists?(connection, 'test_view')).to eq true

        ActiveRecordViews::ChecksumCache.new(connection)

        expect(connection.column_exists?('active_record_views', 'options')).to eq true
        expect(ActiveRecordViews.view_exists?(connection, 'test_view')).to eq true
      end
    end
  end

  describe 'options serialization' do
    let(:dummy_data) { {class_name: 'Test', checksum: '12345'} }
    it 'errors if setting with non-symbol keys' do
      cache = ActiveRecordViews::ChecksumCache.new(connection)
      expect {
        cache.set 'test', dummy_data.merge(options: {'blah' => 123})
      }.to raise_error ArgumentError, 'option keys must be symbols'
    end

    it 'retrieves hash with symbolized keys and preserves value types' do
      options = {foo: 'hi', bar: 123, baz: true}

      cache = ActiveRecordViews::ChecksumCache.new(connection)
      cache.set 'test', dummy_data.merge(options: options)
      expect(cache.get('test')[:options]).to eq options
    end
  end
end
