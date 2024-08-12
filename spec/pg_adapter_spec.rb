# frozen_string_literal: true

RSpec.describe(PgAdapter) do
  it "has a version number" do
    expect(PgAdapter::VERSION).not_to be_nil
  end
end
