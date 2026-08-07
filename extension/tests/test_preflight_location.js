// The preflight's Location field must describe where the job is, not echo part of its title.
// Run: node --test extension/tests/test_preflight_location.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const CAPTURE_PATH = path.join(__dirname, '../capture.js');

function loadCapture() {
    const source = fs.readFileSync(CAPTURE_PATH, 'utf8');
    const sandbox = {};
    const chrome = { runtime: { getManifest: () => ({ version: '0.0.0' }) } };
    // capture.js registers itself on globalThis; give it one we can read back.
    const fn = new Function('globalThis', 'chrome', 'window', 'document', source);
    fn(sandbox, chrome, undefined, undefined);
    return sandbox.jobhuntCapture;
}

const { capturePreflight } = loadCapture();

function preflight({ title = '', visible = '' }) {
    return capturePreflight({ page_title: title, visible_text: visible, selected_text: '', structured_data: [] });
}

describe('capture.js: preflight Location', () => {
    // The regression, taken verbatim from the posting used in the demo recording. The old single-pass
    // regex read "Program Manager" as a city and "Developer" as its region, and because a regex
    // returns the earliest match, that title fragment beat the real location further down the page.
    it('does not read a location out of the job title', () => {
        const p = preflight({
            title: 'Job Application for Principal Technical Program Manager, Developer Productivity at Reddit',
            visible: 'Principal Technical Program Manager, Developer Productivity\nRemote - United States\n$260,800 - $365,100 USD'
        });
        assert.notEqual(p.locationVal, 'Program Manager, Developer');
        assert.equal(p.locationVal, 'Remote - United States');
    });

    it('prefers a named place over a work mode', () => {
        const p = preflight({
            title: 'Senior Engineer at Acme',
            visible: 'Hybrid\nSeattle, WA\nAbout the role'
        });
        assert.equal(p.locationVal, 'Seattle, WA');
    });

    it('reads multi-word cities and spelled-out countries', () => {
        assert.equal(preflight({ visible: 'Office: San Francisco, CA' }).locationVal, 'San Francisco, CA');
        assert.equal(preflight({ visible: 'Based in Toronto, Canada' }).locationVal, 'Toronto, Canada');
        assert.equal(preflight({ visible: 'London, United Kingdom' }).locationVal, 'London, United Kingdom');
    });

    // The half that let "Developer" through: any capitalised word could stand in for a region.
    it('rejects an ordinary capitalised word as a region', () => {
        const p = preflight({ visible: 'Reporting to the Director, Engineering for this team.' });
        assert.equal(p.locationVal, null);
    });

    it('falls back to the work mode when no place is named', () => {
        assert.equal(preflight({ visible: 'This role is Remote.' }).locationVal, 'Remote');
        assert.equal(preflight({ visible: 'Work style: Hybrid' }).locationVal, 'Hybrid');
    });

    it('reports nothing rather than guessing', () => {
        assert.equal(preflight({ title: 'Some Job', visible: 'No location stated anywhere.' }).locationVal, null);
    });
});
