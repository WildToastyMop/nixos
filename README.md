# nixos

My NixOS configs. One directory per machine, everything driven off a flake.

## Hosts

| Host | What it is |
|---|---|
| `power` | home server (runs as a QEMU guest) |
| `proxy` | the public VPS — Caddy edge, DNS, mediaflow |
| `desktop` | daily driver, Hyprland + home-manager |
| `bigscreen` | TV box — Mac mini (Late 2012) running KDE Plasma Bigscreen |

`common.nix` is shared by all of them (users, sops, nix settings, sshd).

## Deploying

```bash
sudo nixos-rebuild switch --flake .#<host>
```

From somewhere else:

```bash
nixos-rebuild switch --flake .#<host> --target-host root@<host>
```

There are `rebuild` and `upgrade` aliases in `common.nix` that use
`$HOSTNAME`, so on the machine itself it's just `rebuild`.

## Secrets

sops-nix. Each host derives its age key from its own SSH host key
(`sops.age.sshKeyPaths` in `common.nix`), so there's no key file to copy around.

The sops config lives in `secrets/.sops.yaml`, not at the repo root — which
matters, because sops looks for it relative to the file you're editing:

```bash
cd secrets && sops updatekeys user-password.yaml --yes
# or be explicit:
sops --config secrets/.sops.yaml updatekeys secrets/user-password.yaml --yes
```

Adding a new host:

1. Get the age recipient of the key that host will actually use at runtime,
   i.e. `/etc/ssh/ssh_host_ed25519_key` on the *installed* system:

   ```bash
   nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'
   ```

2. Add it to `keys:` in `secrets/.sops.yaml`, and to the `key_groups` for the
   secrets that host needs.
3. Re-wrap those files, from a machine that can already decrypt:
   `cd secrets && sops updatekeys user-password.yaml --yes`
4. Commit and push.

## Hardware configs

One per host, at `hosts/<host>/hardware-configuration.nix`. Generate it on the
machine itself and commit the result:

```bash
nixos-generate-config --show-hardware-config \
  > hosts/<host>/hardware-configuration.nix
```

A root-level `hardware-configuration.nix` is gitignored (anchored, so a stray
`nixos-generate-config` in the repo root doesn't get committed by accident).

## Provisioning a machine

`install.sh` runs from a NixOS live ISO (UEFI boot) on the target. It partitions
and formats the disk, writes that host's hardware config, pre-seeds the SSH host
key so you can authorise its sops recipient *before* first boot, then runs
`nixos-install`.

```bash
./install.sh bigscreen --disk /dev/sda            # asks for confirmation
./install.sh bigscreen --disk /dev/sda --dry-run  # print the plan, touch nothing
```

It erases the whole disk — there's no dual-boot mode. `--help` lists everything.

### Low-RAM machines

On a NixOS ISO the writable layer of `/nix/store` is a tmpfs, i.e. RAM, so the
whole closure has to fit in memory. A Plasma desktop is ~14 GiB; a 4 GB box has
~2 GB. `install.sh` sizes the closure up front and refuses rather than wiping a
disk for an install that can't finish.

Use `--bootstrap-minimal` to install a small system instead, then build the real
one on the box where the store is on disk:

```bash
./install.sh bigscreen --disk /dev/sda --bootstrap-minimal

# then, on the box:
nix shell nixpkgs#git -c git clone https://github.com/WildToastyMop/nixos /etc/nixos
nixos-generate-config --show-hardware-config \
  > /etc/nixos/hosts/bigscreen/hardware-configuration.nix
nixos-rebuild switch --flake /etc/nixos#bigscreen
```

A fresh minimal install has no `git` and no nixpkgs channel, hence
`nix shell nixpkgs#git` rather than `nix-shell -p git` — the latter can't
resolve `<nixpkgs>`.

## Things that bit me

- **`sops updatekeys` from the repo root fails** with "config file not found",
  because `.sops.yaml` is in `secrets/`. `cd secrets` first, or pass `--config`.
- **The installer's SSH host key is not the sops key.** An ISO generates a fresh
  key every boot; `install.sh` pre-stages the key that ends up as
  `/etc/ssh/ssh_host_ed25519_key` on the installed system, and *that* is the
  recipient to authorise. Don't regenerate a box's host key later or it loses
  access to its secrets.
- **The first `nixos-rebuild switch` can leave the user's password locked.** On a
  switch, `users-groups` runs before sops writes `/run/secrets/`, so
  `hashedPasswordFile` doesn't exist yet and the account ends up locked (`L` in
  `passwd -S`). A reboot sorts it out, because on boot sops runs first. If you
  need it immediately:
  `usermod -p "$(cat /run/secrets/user-password)" <user>`
- **Detached rebuilds need `PATH` set explicitly.** Seen with `systemd-run`
  wrapping `nixos-rebuild`: systemd's default PATH has no
  `/run/current-system/sw/bin`, and the final activation dies with
  `[Errno 2] No such file or directory: 'test'`. Add
  `-p Environment=PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/bin:/bin`.

## bigscreen

The TV box has its own notes — codec tuning (it only hardware-decodes H.264) and
the matching Jellyfin/YouTube settings live in
[`hosts/bigscreen/README.md`](hosts/bigscreen/README.md).
