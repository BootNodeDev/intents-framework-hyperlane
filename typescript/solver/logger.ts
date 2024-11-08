import chalk, { ChalkInstance } from "chalk";
import { pino } from "pino";

import {
  LogFormat,
  LogLevel,
  configureRootLogger,
  getLogFormat,
  rootLogger,
  safelyAccessEnvVar,
} from "@hyperlane-xyz/utils";

let logger = rootLogger;

export function configureLogger(logFormat: LogFormat, logLevel: LogLevel) {
  logFormat =
    logFormat || safelyAccessEnvVar("LOG_FORMAT", true) || LogFormat.Pretty;
  logLevel = logLevel || safelyAccessEnvVar("LOG_LEVEL", true) || LogLevel.Info;

  logger = configureRootLogger(logFormat, logLevel).child({ module: "solver" });
}

export function logColor(
  level: pino.Level,
  chalkInstance: ChalkInstance,
  ...args: any
) {
  // Only use color when pretty is enabled
  if (getLogFormat() === LogFormat.Pretty) {
    logger[level](chalkInstance(...args));
  } else {
    // @ts-ignore pino type more restrictive than pino's actual arg handling
    logger[level](...args);
  }
}
export const logBlue = (...args: any) => logColor("info", chalk.blue, ...args);
export const logGreen = (...args: any) =>
  logColor("info", chalk.green, ...args);
export const logBoldBlue = (...args: any) =>
  logColor("info", chalk.blue.bold, ...args);
export const logWarn = (...args: any) =>
  logColor("warn", chalk.yellow, ...args);
export const logError = (...args: any) => logColor("error", chalk.red, ...args);

export const logDebug = (msg: string, ...args: any) =>
  logger.debug(msg, ...args);
