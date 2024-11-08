// Hide warn logged by bigint-buffer which solana-web3.js depends on
// see: https://github.com/no2chem/bigint-buffer/issues/31#issuecomment-1752134062
const defaultWarn = console.warn;
console.warn = (...args) => {
  if (
    args &&
    typeof args[0] === "string" &&
    args[0]?.includes("bigint: Failed to load bindings")
  )
    return;
  defaultWarn(...args);
};
