D1 小型合成夹具，不含真人、账号、地址、凭据或生产日志。
依据固定基准 0e33fa615957f4a29174fe4800d7d05862741746：
examples/framework/client_data.gd 的 _record / NUMERIC_FIELDS；
examples/framework/client.gd 的 diagnostic_metrics；
sdk/roomkit/client/room_client.gd 的 _empty_network_diagnostics / _accept_network_observation。
normal.jsonl：稳定、RTT / 快照 / 帧尖峰、两个主观卡顿标记，已成熟 0% 与非零估计。
unknown.jsonl：缺测、不成熟零值、断开后未知，以及第二会话单独归零。
malformed.jsonl：错误 JSON、未知记录、恶意文本、非法数值、单调时钟倒退。
超大文件、超长行、UTF-8 错误与记录上限由测试在内存构造，不交付大日志。
