// ESLint flat config for control-tower (ESLint 10 / Next.js 16).
//
// eslint-config-next v16 ships a flat-config array but it includes
// eslint-plugin-react@7.x which uses the legacy getFilename() API and
// crashes on ESLint >=10. We extract only the TypeScript-ESLint block
// (configs[1]) from eslint-config-next and add @next/next rules via its
// own flat-config export directly.
//
// eslint-plugin-react-hooks is added explicitly (v5 flat-config compatible)
// because configs[0] (which normally carries it) is excluded above.
// Reviewer round 2 finding: react-hooks rules were silenced.
import nextConfig from "eslint-config-next";
import reactHooks from "eslint-plugin-react-hooks";

// configs[0] = react/jsx plugins (crashes on ESLint 10 due to old react plugin)
// configs[1] = typescript-eslint block (safe)
// configs[2] = empty globals block
const [, tsConfig, globalsConfig] = nextConfig;

export default [
  tsConfig,
  globalsConfig,
  {
    plugins: { "react-hooks": reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
    },
  },
  {
    // Ignore build output and generated files
    ignores: [".next/**", "node_modules/**", "*.config.*"],
  },
];
