import { LogFormat } from "@hyperlane-xyz/utils";
import chalk from "chalk";
import { pino, type Level, type Logger } from "pino";
import pretty, { type PrettyOptions } from "pino-pretty";
import uniqolor from "uniqolor";

import { LOG_FORMAT, LOG_LEVEL } from "./config/index.js";

const prettyConfig: PrettyOptions = {
  ignore: "hostname,pid,level",
  messageFormat: (log, msgKey) => {
    const message = `${log[msgKey]}`;

    if (log.name) {
      return chalk.hex(uniqolor(log.name as string).color)(message);
    }

    return message;
  },
};

function createLogger(name?: string, logFormat?: LogFormat, logLevel?: Level) {
  logFormat = logFormat || (LOG_FORMAT as LogFormat) || LogFormat.Pretty;
  logLevel = logLevel || (LOG_LEVEL as Level) || "info";

  const baseConfig = { level: logLevel, name };

  if (logFormat === LogFormat.JSON) {
    return pino(baseConfig);
  }

  return pino(baseConfig, pretty(prettyConfig));
}

const log = createLogger();

export { createLogger, log, LogFormat, type Level, type Logger };
