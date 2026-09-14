import { test, expect } from '@playwright/test';
import { DesktopBrowserHarness } from './support/desktop_browser_harness.js';

for (const mode of ['Text', 'Code']) {
  test(`${mode} results keep previews aligned and support keyboard navigation`, async ({ page }) => {
    const app = new DesktopBrowserHarness(page);
    app.workingFiles['src/main.mbt'] = 'fn main {\n  inspect(\n    "moon moon",\n  )\n}\n';
    app.textSearchMatches = [{
      path: 'src/main.mbt', line_number: 3,
      preview: '    "moon moon",', preview_start_column: 1,
      ranges: [{ start_column: 6, end_column: 10 }, { start_column: 11, end_column: 15 }],
    }];
    app.textSearchMatchCount = 2;
    app.semanticSearchMatches = [{
      path: 'src/main.mbt', rule_id: 'inspect($(argument:arg))'.repeat(15),
      description: 'A long rule name must fit within the result panel.',
      start_line: 2, start_column: 3, end_line: 4, end_column: 4,
      matched_source: 'inspect(\n    "moon moon",\n  )',
      source_context: app.workingFiles['src/main.mbt'].trimEnd().split('\n').map((text, index) => ({
        line: index + 1, text, is_match: index >= 1 && index <= 3,
      })),
    }];
    // Both providers can finish with useful rows and a diagnostic.
    const replyFor = app.replyFor.bind(app);
    let scanFailed = false;
    app.replyFor = request => {
      const reply = replyFor(request);
      if (scanFailed && ['fs.search_text', 'fs.search_semantic'].includes(request.method)) {
        return { ...reply, error_code: 'search_failed', error_message: 'One file could not be read.' };
      }
      return reply;
    };
    await app.install();
    await app.goto();
    await app.openSession();
    const shortcut = await page.evaluate(() =>
      navigator.platform.includes('Mac') ? 'Meta+Shift+F' : 'Control+Shift+F');
    await page.keyboard.press(shortcut);
    if (mode === 'Code') {
      await page.getByRole('button', { name: 'Code search', exact: true }).click();
      await page.getByRole('textbox', { name: 'pattern', exact: true }).fill('inspect($(x:arg))');
    } else {
      await page.getByRole('textbox', { name: 'Search', exact: true }).fill('moon');
    }
    const results = page.locator('.search-results');
    const row = results.getByRole('button', { name: mode === 'Text' ? /moon moon/ : /inspect/ });
    await expect(row).toBeVisible();
    await expect(results.locator('.search-summary')).toHaveText(
      mode === 'Text' ? '2 matches in 1 file' : '1 match in 1 file',
    );
    await expect(row.locator('.search-match-highlight')).toHaveText(
      mode === 'Text' ? ['moon', 'moon'] : ['inspect(', '    "moon moon",', '  )'],
    );
    // These are browser geometry contracts: long metadata must not widen the
    // panel, and every preview line must share its gutter and text columns.
    const geometry = await row.evaluate(element => {
      const rect = element.getBoundingClientRect();
      const panel = element.closest('.search-results').getBoundingClientRect();
      return {
        overflow: Math.max(0, rect.right - panel.right),
        textStarts: [...element.querySelectorAll('.search-result-preview')].map(node => node.getBoundingClientRect().left),
      };
    });
    expect(geometry.overflow).toBeLessThanOrEqual(1);
    expect(Math.max(...geometry.textStarts) - Math.min(...geometry.textStarts)).toBeLessThanOrEqual(1);
    await row.focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('#viewer-host .view-lines')).toContainText('moon moon');
    const header = results.getByRole('button', { name: /main.mbt.*src/ });
    await header.click();
    await expect(row).toBeHidden();
    await header.click();
    await expect(row).toBeVisible();
    scanFailed = true;
    await page.locator('.workspace-search').getByRole('button', { name: 'Refresh', exact: true }).click();
    await expect(results.getByRole('alert')).toContainText('One file could not be read.');
    await expect(row).toBeVisible();
    expect(app.pageErrors).toEqual([]);
  });
}
