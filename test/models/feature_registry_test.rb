require "test_helper"

class FeatureRegistryTest < ActiveSupport::TestCase
  test "sync! is idempotent" do
    key = "widget_beta_#{SecureRandom.hex(4)}"

    with_feature_config(key => { "name" => "Widget Beta" }) do
      FeatureRegistry.sync!
      assert_no_difference "Feature.count" do
        FeatureRegistry.sync!
      end
    end
  end

  test "an admin's enabled toggle on an existing feature survives a re-sync" do
    key = "widget_beta_#{SecureRandom.hex(4)}"
    feature = Feature.create!(key: key, name: "Widget Beta")
    feature.update!(enabled: true)

    with_feature_config(key => { "name" => "Widget Beta" }) do
      FeatureRegistry.sync!
    end

    assert feature.reload.enabled?
  end

  private

  # Points FeatureRegistry at a temporary YAML file for the duration of the block,
  # instead of the real config/features.yml, so tests don't depend on (or mutate) it.
  def with_feature_config(config)
    original = FeatureRegistry::CONFIG_PATH
    tempfile = Tempfile.new([ "features", ".yml" ])
    tempfile.write(config.to_yaml)
    tempfile.close

    FeatureRegistry.send(:remove_const, :CONFIG_PATH)
    FeatureRegistry.const_set(:CONFIG_PATH, Pathname.new(tempfile.path))

    yield
  ensure
    FeatureRegistry.send(:remove_const, :CONFIG_PATH)
    FeatureRegistry.const_set(:CONFIG_PATH, original)
    tempfile&.unlink
  end
end
