### Event driven state machines example
#### Timers, signals, reading from stdin

* compile with `zig build-exe test.zig -fsingle-threaded -O ReleaseSmall`
* run `./test`
* type something (end with `Enter`) while it's running and see what will happen

```
Hi! I am 'TEST-SM'. Press ^C to stop me.
You can also type something and press Enter

tick #1 (nexp = 1)
tick #2 (nexp = 1)
tick #3 (nexp = 1)
tick #4 (nexp = 1)
tick #5 (nexp = 1)
435t45
have 7 bytes
you entered '435t45'
tick #6 (nexp = 1)
tick #7 (nexp = 1)
345ttick #8 (nexp = 1)
45t
have 8 bytes
you entered '345t45t'
tick #9 (nexp = 1)
tick #10 (nexp = 1)
tick #11 (nexp = 1)
```

* now switch to another terminal and send `SIGTERM` to the `./test`

```
got signal #15 from PID 1597 after 26 ticks
Bye! It was 'TEST-SM'.
```
