import { describe, expect, it } from "vitest";
import { isAllowedIntent } from "../config";
import {
  type AllowBlockLists,
  AllowBlockListItemSchema,
} from "../config/types";

describe("config schema", () => {
  it("invalid config - wildcard in array", () => {
    const parsed = AllowBlockListItemSchema.safeParse({
      senderAddress: ["*"],
      destinationDomain: ["*"],
      recipientAddress: ["*"],
    });

    expect(parsed.success).toBeFalsy();
    expect(parsed.error?.errors[0].message).toBe("Invalid address");
    expect(parsed.error?.errors[1].message).toBe("Invalid domain");
    expect(parsed.error?.errors[2].message).toBe("Invalid address");
  });

  it("invalid config - invalid data string", () => {
    const parsed = AllowBlockListItemSchema.safeParse({
      senderAddress: "invalid address",
      destinationDomain: "invalid domain",
      recipientAddress: "*",
    });

    expect(parsed.success).toBeFalsy();
    expect(parsed.error?.errors[0].message).toBe("Invalid address");
    expect(parsed.error?.errors[1].message).toBe("Invalid domain");
  });

  it("invalid config - invalid data in array", () => {
    const parsed = AllowBlockListItemSchema.safeParse({
      senderAddress: [
        "0xca7f632e91B592178D83A70B404f398c0a51581F",
        "invalid address",
      ],
      destinationDomain: ["mainnet", "invalid domain"],
      recipientAddress: "*",
    });

    expect(parsed.success).toBeFalsy();
    expect(parsed.error?.errors[0].message).toBe("Invalid address");
    expect(parsed.error?.errors[1].message).toBe("Invalid domain");
  });

  it("valid config - single values", () => {
    const parsed = AllowBlockListItemSchema.safeParse({
      senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
      destinationDomain: "ethereum",
      recipientAddress: "*",
    });

    console.log(parsed.error);
    expect(parsed.success).toBeTruthy();
  });

  it("valid config - multi values", () => {
    const parsed = AllowBlockListItemSchema.safeParse({
      senderAddress: [
        "0xca7f632e91B592178D83A70B404f398c0a51581F",
        "0xca7f632e91B592178D83A70B404f398c0a51581F",
      ],
      destinationDomain: ["ethereum", "optimism"],
      recipientAddress: "*",
    });

    expect(parsed.success).toBeTruthy();
  });
});

describe("isAllowedIntent", () => {
  it("intent not allowed by destination", () => {
    const allowBlockLists: AllowBlockLists = {
      allowList: [],
      blockList: [
        {
          senderAddress: "*",
          destinationDomain: ["ethereum"],
          recipientAddress: "*",
        },
      ],
    };
    expect(
      isAllowedIntent(allowBlockLists, {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "ethereum",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
      }),
    ).toBeFalsy();
  });

  it("intent not allowed by sender", () => {
    const allowBlockLists: AllowBlockLists = {
      allowList: [],
      blockList: [
        {
          senderAddress: ["0xca7f632e91B592178D83A70B404f398c0a51581F"],
          destinationDomain: "*",
          recipientAddress: "*",
        },
      ],
    };
    expect(
      isAllowedIntent(allowBlockLists, {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "ethereum",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
      }),
    ).toBeFalsy();
  });

  it("intent not allowed by recipientAddress", () => {
    const allowBlockLists: AllowBlockLists = {
      allowList: [],
      blockList: [
        {
          senderAddress: "*",
          destinationDomain: "*",
          recipientAddress: ["0xca7f632e91B592178D83A70B404f398c0a51581F"],
        },
      ],
    };
    expect(
      isAllowedIntent(allowBlockLists, {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "ethereum",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
      }),
    ).toBeFalsy();
  });

  it("makes sure that blocklist supersedes allowlist", () => {
    const allowBlockLists: AllowBlockLists = {
      allowList: [
        {
          senderAddress: "*",
          destinationDomain: "*",
          recipientAddress: ["0xca7f632e91B592178D83A70B404f398c0a51581a"],
        },
      ],
      blockList: [
        {
          senderAddress: "*",
          destinationDomain: "*",
          recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581A",
        },
      ],
    };

    expect(
      isAllowedIntent(allowBlockLists, {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "ethereum",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581a",
      }),
    ).toBeFalsy();
  });

  it("assures that allowList wildcards work as expected", () => {
    const allowBlockLists: AllowBlockLists = {
      allowList: [
        {
          senderAddress: "*",
          destinationDomain: "*",
          recipientAddress: "*",
        },
      ],
      blockList: [],
    };

    expect(
      isAllowedIntent(allowBlockLists, {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "ethereum",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581a",
      }),
    ).toBeTruthy();
  });

  it("assures that blockList wildcards work as expected", () => {
    const allowBlockLists: AllowBlockLists = {
      allowList: [],
      blockList: [
        {
          senderAddress: "*",
          destinationDomain: "*",
          recipientAddress: "*",
        },
      ],
    };

    expect(
      isAllowedIntent(allowBlockLists, {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "1",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581a",
      }),
    ).toBeFalsy();
  });

  it("properly filters out intents that are not allowed", () => {
    const allowBlockLists: AllowBlockLists = {
      allowList: [],
      blockList: [
        {
          senderAddress: "*",
          destinationDomain: ["optimism", "base"],
          recipientAddress: "*",
        },
      ],
    };

    [
      {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "optimism",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        expected: false,
      },
      {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "base",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        expected: false,
      },
      {
        senderAddress: "0xca7f632e91B592178D83A70B404f398c0a51581F",
        destinationDomain: "ethereum",
        recipientAddress: "0xca7f632e91B592178D83A70B404f398c0a51581A",
        expected: true,
      },
    ].forEach((test) => {
      expect(
        isAllowedIntent(allowBlockLists, {
          senderAddress: test.senderAddress,
          destinationDomain: test.destinationDomain,
          recipientAddress: test.recipientAddress,
        }),
      ).toBe(test.expected);
    });
  });
});
