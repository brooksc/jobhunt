# Contributing

Bug reports and pull requests are welcome.

## Reporting issues

Open an issue at [github.com/brooksc/jobhunt/issues](https://github.com/brooksc/jobhunt/issues). Include your macOS version, Node.js version, and steps to reproduce.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Run the test suite before submitting: `npm test && npm run lint`
3. Keep changes focused — one fix or feature per PR.
4. Update the README if your change affects setup or usage.

## Development setup

```bash
npm install
npm start        # supervised server at http://127.0.0.1:8765
npm test         # unit + integration tests
npm run lint
```

See the [Developer Guide](README.md#developer-guide) in the README for full details.
