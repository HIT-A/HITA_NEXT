export interface DeleteEffectPlayer {
  start: (finish: () => void, ready: () => void) => void;
  stop: () => void;
}

export const DELETE_PREPARE_TIMEOUT: number = 1600;
export const DELETE_PLAYBACK_TIMEOUT: number = 3000;

/** Visual completion is bounded and can never reject a successful database deletion. */
export class DeleteEffectController {
  private players: Map<string, DeleteEffectPlayer> = new Map<string, DeleteEffectPlayer>();
  private pending: Map<string, () => void> = new Map<string, () => void>();
  private active: boolean = true;

  register(id: string, player: DeleteEffectPlayer): void {
    const previous: DeleteEffectPlayer | undefined = this.players.get(id);
    if (previous !== undefined) {
      this.unregister(id, previous);
    }
    this.players.set(id, player);
  }

  unregister(id: string, player: DeleteEffectPlayer): void {
    if (this.players.get(id) !== player) {
      return;
    }
    const finish: (() => void) | undefined = this.pending.get(id);
    if (finish !== undefined) {
      finish();
    }
    this.players.delete(id);
  }

  resume(): void {
    this.active = true;
  }

  pause(): void {
    this.active = false;
    const completions: Array<() => void> = Array.from(this.pending.values());
    completions.forEach((finish: () => void) => finish());
  }

  async play(ids: string[]): Promise<void> {
    const jobs: Promise<void>[] = [];
    for (const id of ids) {
      jobs.push(this.playOne(id));
    }
    await Promise.all(jobs);
  }

  private playOne(id: string): Promise<void> {
    const player: DeleteEffectPlayer | undefined = this.players.get(id);
    // Bound batch deletion cost; unmounted/offscreen cards need no visual effect.
    if (!this.active || player === undefined || this.pending.has(id) || this.pending.size >= 3) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      let completed: boolean = false;
      let started: boolean = false;
      let timer: number = -1;
      const finish = (): void => {
        if (completed) {
          return;
        }
        completed = true;
        clearTimeout(timer);
        this.pending.delete(id);
        try {
          player.stop();
        } catch (_) {
        }
        resolve();
      };
      const ready = (): void => {
        if (completed || started) {
          return;
        }
        started = true;
        clearTimeout(timer);
        timer = setTimeout(finish, DELETE_PLAYBACK_TIMEOUT);
      };
      this.pending.set(id, finish);
      timer = setTimeout(finish, DELETE_PREPARE_TIMEOUT);
      try {
        player.start(finish, ready);
      } catch (_) {
        finish();
      }
    });
  }
}
