import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = process.cwd();
const source = readFileSync(resolve(root, 'imagehost-new-project-kit/documents/requirements-analysis.md'), 'utf8').replaceAll('\r\n', '\n');
const coverage = readFileSync(resolve(root, 'docs/windows-v1-coverage.md'), 'utf8').replaceAll('\r\n', '\n');
const requirements = [...source.matchAll(/^### ([A-Z]+-\d{3}) .+$/gm)];
let count = 0;
for (const entry of requirements) {
  const after = source.slice(entry.index + entry[0].length);
  const next = after.search(/^#{1,3} /m);
  const business = (next < 0 ? after : after.slice(0, next)).trim();
  if (!business.split('\n')[0].includes('｜V1｜')) continue;
  count++;
  const heading = new RegExp(`^#### ${entry[1]} .+$`, 'm').exec(coverage);
  if (!heading) throw new Error(`Missing V1 requirement ${entry[1]}`);
  const block = coverage.slice(heading.index + heading[0].length).trimStart();
  if (!block.startsWith(business)) throw new Error(`Changed normative text ${entry[1]}`);
}
if (count !== 90) throw new Error(`Expected 90 V1 requirements, found ${count}`);
console.log('PASS preserved all 90 V1 requirement attributes, behavior and acceptance wording');
