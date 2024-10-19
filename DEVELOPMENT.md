# Development

Development instructions.

## Update latest version

Update latest version only when there are backward compatible changes.

```
git commit -A -m "Fix XYZ" \
  && git push \
  && git tag "v1" --force \
  && git push --tags --force
```
