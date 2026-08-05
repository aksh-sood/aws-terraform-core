# modules/jaeger

Tracing, taken straight from the Istio release's own sample addon rather than
re-templated here.

## Creates

- The Jaeger manifests from
  `https://raw.githubusercontent.com/istio/istio/release-<major.minor>/samples/addons/jaeger.yaml`,
  fetched at plan time with `data "http"` and split with
  `kubectl_file_documents`
- A `VirtualService` routing `<environment>-jaeger.<domain_name>` to the `tracing`
  service, through the `istio-gateway` Gateway that
  [../istio](../istio/README.md) creates

The release branch is derived from `istio_version` by regex, so
`v1.30.3` reads `release-1.30`.

## Inputs

`environment`, `istio_version`, `domain_name`. Requires the `kubectl.this`
provider alias.

## Gotchas

- **`kubectl_manifest.crd` has a hardcoded `count = 4`.** Terraform cannot vary a
  resource count from a value discovered during the same plan, so the number of
  documents in the upstream file is pinned by hand. **Changing `istio_version`
  means checking that count against the new file** — too low silently skips
  objects, too high fails the plan.
- Nothing pins the upstream file's contents. A re-plan after Istio retags a
  release branch can produce a diff that has nothing to do with this repository.
- The UI is behind the basic auth WasmPlugin in `../istio`; the password is the
  `jaeger_password` output of the root module.
