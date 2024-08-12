export VERSION=$1
echo "VERSION: ${VERSION}"

echo "=== Pushing tags to github ===="
git tag v"$VERSION"
git push origin --tags

echo "=== Building Gem ===="
gem build pg-adapter.gemspec

echo "=== Pushing gem ===="
gem push pg-adapter-"$VERSION".gem

echo "=== Cleaning up ===="
rm pg-adapter-"$VERSION".gem
