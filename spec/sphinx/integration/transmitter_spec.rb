# coding: utf-8
require 'spec_helper'

describe Sphinx::Integration::Transmitter do
  let!(:record){ ModelWithRt.create!(:content => 'test content') }
  let(:connection){ mock(Sphinx::Integration::Mysql::Connection) }

  before(:all){ ThinkingSphinx.context.define_indexes }

  before do
    ThinkingSphinx.stub(:take_connection).and_yield(connection)
  end

  subject { record.transmitter }

  context 'when destroy' do
    let(:delete_sql){ 'DELETE FROM model_with_rt_rt WHERE id = %s' }
    let(:delete_delta_sql){ 'DELETE FROM model_with_rt_delta_rt WHERE id = %s' }

    it 'delete in rt' do
      connection.should_receive(:execute).with(delete_sql % record.sphinx_document_id).once
      subject.delete
    end

    context 'when full reindex' do
      it 'delete in delta_rt' do
        Redis::Mutex.with_lock(:full_reindex, :expire => 3.hours) do
          connection.should_receive(:execute).with(delete_sql % record.sphinx_document_id).ordered
          connection.should_receive(:execute).with(delete_delta_sql % record.sphinx_document_id).ordered
          subject.delete
        end
      end
    end
  end

  context 'when save' do
    it 'replace in rt' do
      connection.should_receive(:execute).with(RSpec::Mocks::ArgumentMatchers::RegexpMatcher.new(/^REPLACE INTO model_with_rt_rt/)).once
      subject.replace
    end

    context 'when full reindex' do
      it 'replace in delta_rt' do
        Redis::Mutex.with_lock(:full_reindex, :expire => 3.hours) do
          connection.should_receive(:execute).with(RSpec::Mocks::ArgumentMatchers::RegexpMatcher.new(/^REPLACE INTO model_with_rt_rt/)).ordered
          connection.should_receive(:execute).with(RSpec::Mocks::ArgumentMatchers::RegexpMatcher.new(/^REPLACE INTO model_with_rt_delta_rt/)).ordered
          subject.replace
        end
      end
    end
  end
end