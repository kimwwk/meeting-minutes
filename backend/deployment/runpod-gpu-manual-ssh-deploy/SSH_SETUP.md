# SSH Key Setup for RunPod

## Step 1: Generate SSH Key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/runpod_meetily -C "runpod-meetily"
```

## Step 2: Add Public Key to RunPod

1. Copy your public key:
   ```bash
   cat ~/.ssh/runpod_meetily.pub
   ```

2. Paste into: **RunPod Dashboard → Settings → SSH Public Keys**

## Step 3: Connect to Pod

```bash
ssh root@<POD_IP> -p <PORT> -i ~/.ssh/runpod_meetily
```

On first connect, type `yes` to accept the host key.

## Step 4: Copy Files to Pod

```bash
scp -P <PORT> -i ~/.ssh/runpod_meetily <LOCAL_FILE> root@<POD_IP>:/workspace/
```

## Optional: SSH Config

Add to `~/.ssh/config` for easier access:

```
Host runpod-meetily
    HostName <POD_IP>
    Port <PORT>
    User root
    IdentityFile ~/.ssh/runpod_meetily
    StrictHostKeyChecking no
```

Then connect with: `ssh runpod-meetily`

**Note:** Update `<POD_IP>` and `<PORT>` each time you start a new pod.

## Cleanup

```bash
rm -f ~/.ssh/runpod_meetily ~/.ssh/runpod_meetily.pub
# Also remove from RunPod dashboard
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Permission denied | `chmod 600 ~/.ssh/runpod_meetily` |
| Connection refused | Check pod is running, get new port from dashboard |
| Host key failed | `ssh-keygen -R "[<POD_IP>]:<PORT>"` |
