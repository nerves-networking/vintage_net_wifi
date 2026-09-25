// SPDX-FileCopyrightText: 2026 Cocoa Xu
//
// SPDX-License-Identifier: Apache-2.0
//
#include <err.h>
#include <stdlib.h>
#include <string.h>
#include <net/if.h>
#include <netlink/genl/genl.h>
#include <netlink/genl/ctrl.h>
#include <linux/nl80211.h>

int main(int argc, char **argv)
{
    if (argc != 3)
        errx(EXIT_FAILURE, "Usage: tx_power <ifname> <mBm | auto>");

    uint32_t ifindex = if_nametoindex(argv[1]);
    if (ifindex == 0)
        errx(EXIT_FAILURE, "Specify a WiFi device that works: %s", argv[1]);

    struct nl_sock *nl_sock = nl_socket_alloc();
    if (!nl_sock)
        err(EXIT_FAILURE, "nl_socket_alloc");

    if (genl_connect(nl_sock))
        err(EXIT_FAILURE, "genl_connect");

    int nl80211_id = genl_ctrl_resolve(nl_sock, "nl80211");
    if (nl80211_id < 0)
        err(EXIT_FAILURE, "genl_ctrl_resolve(nl80211)");

    struct nl_msg *msg = nlmsg_alloc();
    if (!msg)
        err(EXIT_FAILURE, "nlmsg_alloc");

    genlmsg_put(msg, 0, 0, nl80211_id, 0, 0, NL80211_CMD_SET_WIPHY, 0);
    nla_put_u32(msg, NL80211_ATTR_IFINDEX, ifindex);

    if (strcmp(argv[2], "auto") == 0) {
        nla_put_u32(msg, NL80211_ATTR_WIPHY_TX_POWER_SETTING, NL80211_TX_POWER_AUTOMATIC);
    } else {
        char *end;
        long mbm = strtol(argv[2], &end, 10);
        if (*argv[2] == '\0' || *end != '\0')
            errx(EXIT_FAILURE, "Invalid tx power in mBm: %s", argv[2]);

        nla_put_u32(msg, NL80211_ATTR_WIPHY_TX_POWER_SETTING, NL80211_TX_POWER_FIXED);
        nla_put_u32(msg, NL80211_ATTR_WIPHY_TX_POWER_LEVEL, (uint32_t) mbm);
    }

    int rc = nl_send_sync(nl_sock, msg);
    if (rc < 0)
        errx(EXIT_FAILURE, "Setting tx power on %s failed: %s", argv[1], nl_geterror(rc));

    nl_socket_free(nl_sock);
    return 0;
}
