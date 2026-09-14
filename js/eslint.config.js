import globals from "globals";

/** @type {import('eslint').Linter.Config[]} */
export default [
	{
		ignores: ["node_modules/", "reports/", "scratch/", "dist/", "**/*.min.js"],
	},
	{
		files: [
			"core/src/**/*.js",
			"core/test/**/*.js",
			"cucumber/src/**/*.js",
			"cucumber/test/**/*.js",
			"cli/src/**/*.js",
			"cli/bin/**/*.js",
			"cli/test/**/*.js",
			"visual/src/**/*.js",
			"visual/test/**/*.js",
			"examples/**/*.js",
		],
		languageOptions: {
			ecmaVersion: 2022,
			sourceType: "module",
			globals: {
				...globals.node,
				...globals.es2022,
			},
		},
		linterOptions: {
			reportUnusedDisableDirectives: "warn",
		},
		rules: {
			// Style is enforced by tabs + existing conventions; keep lint on correctness.
			indent: "off",
			quotes: "off",
			semi: ["error", "always"],
			"no-var": "error",
			"prefer-const": ["error", { destructuring: "all" }],
			eqeqeq: ["error", "always", { null: "ignore" }],
			curly: ["error", "all"],
			"no-unused-vars": ["warn", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
			"no-throw-literal": "error",
			"no-async-promise-executor": "error",
			"require-atomic-updates": "warn",
			"no-console": "off",
		},
	},
];
