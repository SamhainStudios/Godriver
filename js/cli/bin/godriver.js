#!/usr/bin/env node

import { runCli } from "../src/index.js";

runCli(process.argv.slice(2))
	.then((code) => {
		process.exit(code);
	})
	.catch((err) => {
		console.error(err);
		process.exit(2);
	});
