
sudo rpm -Va

\t[S]: File size differs
\t[M]: Mode (permissions or file type) differs
\t[5]: MD5/SHA differs (the file content has changed)
\t[D]: Device major/minor number mismatch
\t[U]: User ownership differs 
\t[G]: Group ownership differs
\t[T]: Modification time differs
\t[P]: Capabilities differ
\t[missing] : The file was part of a package but has been deleted
\t[c] Indicates a configuration file , its normal for these to change as you customize your system
\t[.]: (A dot) means that specific test passed

Log Audit :
cd /var/log/qubes
cd /var/log/xen

Anti-Evil-Maid :
sudo qubes-dom0-update anti-evil-maid
