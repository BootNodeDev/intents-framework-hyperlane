import { createClient, type Config } from "@libsql/client";

let clientConfig: Config = {
  url: "file:local.db",
};

const db = createClient(clientConfig);

const createTable = `
    CREATE TABLE IF NOT EXISTS openOrders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      originChainId INTEGER,
      destinationChainId INTEGER,
      destinationChainSettler TEXT,
      orderId TEXT,
      fillDeadline INTEGER,
      orderData TEXT,
      status TEXT
    )
`;

const fillDeadlineIndex = `CREATE INDEX IF NOT EXISTS idx_fillDeadline ON openOrders (fillDeadline DESC)`;
const orderIdUniqueIndex = `CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_orderId ON openOrders (orderId)`;

await db.batch([createTable, fillDeadlineIndex, orderIdUniqueIndex], "write");

export const getExpiredOrders = async (currentTimestamp: number) => {
  const result = await db.execute({
    sql: `SELECT originChainId, destinationChainId, destinationChainSettler, orderId, fillDeadline, orderData, status
      FROM openOrders
      WHERE fillDeadline <= :currentTimestamp AND status = 'OPEN'
    `,
    args: {
      currentTimestamp
    }
  });

  return result.rows.reduce(
    (acc, current) => {
      if (!acc[current["destinationChainId"] as string]) {
        acc[current["destinationChainId"] as string] = []
      }

      acc[current["destinationChainId"] as string].push({
        originChainId: current["originChainId"] as number,
        destinationChainId: current["destinationChainId"] as number,
        destinationChainSettler: current["destinationChainSettler"] as string,
        orderId: current["orderId"] as string,
        fillDeadline: current["fillDeadline"] as number,
        orderData: current["orderData"] as string,
        status: current["status"] as string
      });

      return acc;
    },
    {} as Record<
      string,
      Array<{
        originChainId: number;
        destinationChainId: number;
        destinationChainSettler: string;
        orderId: string;
        fillDeadline: number;
        orderData: string;
        status: string;
      }>
    >,
  );
};

export const saveOpenOrder = (
  originChainId: number,
  destinationChainId: number,
  destinationChainSettler: string,
  orderId: string,
  fillDeadline: number,
  orderData: string
) => {
  db.execute({
    sql: `INSERT OR IGNORE INTO openOrders (originChainId, destinationChainId, destinationChainSettler, orderId, fillDeadline, orderData, status)
    VALUES (:originChainId, :destinationChainId, :destinationChainSettler, :orderId, :fillDeadline, :orderData, :status)`,
    args: {
      originChainId,
      destinationChainId,
      destinationChainSettler,
      orderId,
      fillDeadline,
      orderData,
      status: 'OPEN'
    },
  });
};

export const saveOrderStatus = (
  orderId: string,
  status: string
) => {
  db.execute({
    sql: `UPDATE openOrders SET status = :status WHERE orderId = :orderId`,
    args: {
      orderId,
      status
    },
  });
};

export default db;
