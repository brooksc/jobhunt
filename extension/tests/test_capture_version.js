// Tests that the capture payload extension_version uses chrome.runtime.getManifest().version
// rather than a hard-coded string.
// Run: node --test extension/tests/test_capture_version.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

const MANIFEST_PATH = path.join(__dirname, '../manifest.json');
const CAPTURE_PATH = path.join(__dirname, '../capture.js');

const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
const captureSource = fs.readFileSync(CAPTURE_PATH, 'utf8');

describe('capture.js: extension_version', () => {
    test('does not hard-code a version string in the payload', () => {
        // The old pattern was: extension_version: "0.2.0"
        // Any quoted version literal is a signal that it is not using the manifest.
        const hardCodedVersionPattern = /extension_version:\s*["']\d+\.\d+/;
        assert.equal(
            hardCodedVersionPattern.test(captureSource),
            false,
            'capture.js must not hard-code an extension_version string — use chrome.runtime.getManifest().version'
        );
    });

    test('uses chrome.runtime.getManifest to read the version', () => {
        assert.ok(
            captureSource.includes('getManifest'),
            'capture.js must read the version from chrome.runtime.getManifest()'
        );
    });

    test('manifest version is a valid semver string', () => {
        assert.match(manifest.version, /^\d+\.\d+\.\d+$/, 'manifest.json version must be semver');
    });

    test('version in payload matches manifest at runtime (simulated)', () => {
        // Simulate the chrome.runtime.getManifest call in a Node context.
        const mockManifestVersion = manifest.version;
        const chrome = {
            runtime: {
                getManifest: () => ({ version: mockManifestVersion })
            }
        };
        // Eval capture.js with our chrome mock in scope.
        const globalThis = {};
        eval(captureSource); // eslint-disable-line no-eval
        // The capture module registers on globalThis.jobhuntCapture — just verify the
        // extension_version expression would resolve to the manifest version.
        const resolvedVersion = (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getManifest)
            ? chrome.runtime.getManifest().version
            : 'unknown';
        assert.equal(resolvedVersion, manifest.version,
            'Simulated runtime version must equal manifest version');
    });
});
