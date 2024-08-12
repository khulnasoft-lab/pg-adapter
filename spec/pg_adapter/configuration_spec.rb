# frozen_string_literal: true

RSpec.describe(PgAdapter::Configuration) do
  after :each do
    PgAdapter.reset_configuration
  end

  describe "new" do
    it "initializes with the passed attributes" do
      c = described_class.new({
        add_failover_patch: true,
        add_reset_column_information_patch: true,
      })

      expect(c.add_failover_patch).to be(true)
      expect(c.add_reset_column_information_patch).to be(true)
    end

    it "initializes with the defaults" do
      c = PgAdapter.configuration

      expect(c.add_failover_patch).to be(false)
      expect(c.add_reset_column_information_patch).to be(false)
    end
  end

  describe "yields" do
    it "correctly with the passed attributes" do
      PgAdapter.configure do |c|
        c.add_failover_patch = true
        c.add_reset_column_information_patch = true
      end

      config = PgAdapter.configuration

      expect(config.add_failover_patch).to be(true)
      expect(config.add_reset_column_information_patch).to be(true)
    end
  end

  describe ".failover_patch?" do
    it "returns false" do
      expect(PgAdapter.failover_patch?).to be(false)
    end

    it "returns true" do
      PgAdapter.configure do |c|
        c.add_failover_patch = true
      end
      expect(PgAdapter.failover_patch?).to be(true)
    end
  end

  describe ".reset_column_information_patch?" do
    it "returns false" do
      expect(PgAdapter.reset_column_information_patch?).to be(false)
    end

    it "returns true" do
      PgAdapter.configure do |c|
        c.add_reset_column_information_patch = true
      end
      expect(PgAdapter.reset_column_information_patch?).to be(true)
    end
  end
end
