# Security

The controller reads database credentials from the local `mangosd.conf` only
at runtime. It does not contain or transmit credentials. Do not attach server
configuration files, database dumps, or unredacted logs to public issues.

Report suspected credential exposure privately to the repository owner before
opening a public issue. Ordinary compatibility bugs may be reported publicly
after all passwords, addresses, account details, and personal screenshots have
been removed.
