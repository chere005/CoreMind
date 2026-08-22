// The canon suite's config lives OUTSIDE canon/ deliberately: canon holds
// byte-for-byte copies of the consumers' files, and a config dropped in there
// would be a file no consumer has.
//
// The two excluded tests are the server-protocol checks (REC_ID_RE,
// MAX_BATCH): canon carries CalMind's copies, which read the server from
// CalMind's own tree — a tree this repo does not have. They still run in
// CalMind (in-repo) and in ChefMind (via the sibling checkout); excluding
// them HERE loses nothing that was ever covered here.
import { defineConfig, configDefaults } from 'vitest/config';

export default defineConfig({
  test: {
    exclude: [...configDefaults.exclude, '**/protocolids.test.ts', '**/batchlimit.test.ts'],
  },
});
