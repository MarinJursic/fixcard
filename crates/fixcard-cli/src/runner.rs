//! Explicit, bounded command capture for one-step lookup.

use std::collections::VecDeque;
use std::ffi::{OsStr, OsString};
use std::io::{self, Read, Write};
use std::process::{Command, ExitCode, Stdio};
use std::thread;

use anyhow::{Context, Result, anyhow, bail};
use fixcard_git::Repository;

use crate::{FindArgs, find_query, output_to_stderr};

const CAPTURE_BYTES_PER_STREAM: usize = 512 * 1024;
const READ_BUFFER_BYTES: usize = 16 * 1024;

pub(super) fn run_and_find(
    repository: Option<&Repository>,
    command: &[OsString],
) -> Result<ExitCode> {
    let (program, arguments) = command
        .split_first()
        .ok_or_else(|| anyhow!("run requires a program after `--`"))?;
    if program.is_empty() {
        bail!("run requires a non-empty program")
    }
    #[cfg(target_os = "windows")]
    if std::path::Path::new(program)
        .extension()
        .and_then(OsStr::to_str)
        .is_some_and(|extension| matches!(extension.to_ascii_lowercase().as_str(), "bat" | "cmd"))
    {
        bail!("run refuses .bat and .cmd programs because Windows invokes them through a shell")
    }

    let mut child = Command::new(program)
        .args(arguments)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("cannot run `{}`", program.to_string_lossy()))?;
    let child_stdout = child
        .stdout
        .take()
        .context("cannot capture command stdout")?;
    let child_stderr = child
        .stderr
        .take()
        .context("cannot capture command stderr")?;

    let stdout_thread = thread::spawn(move || tee_tail(child_stdout, io::stdout()));
    let stderr_thread = thread::spawn(move || tee_tail(child_stderr, io::stderr()));
    let status = child
        .wait()
        .context("cannot wait for the captured command")?;
    let stdout_tail = join_capture(stdout_thread, "stdout")?;
    let stderr_tail = join_capture(stderr_thread, "stderr")?;

    if status.success() {
        return Ok(ExitCode::SUCCESS);
    }

    let mut query = format!(
        "command: {}\nexit status: {}\n",
        display_command(program, arguments),
        status
    );
    query.push_str(&String::from_utf8_lossy(&stderr_tail));
    query.push('\n');
    query.push_str(&String::from_utf8_lossy(&stdout_tail));
    let _output_guard = output_to_stderr();
    let _ = find_query(repository, &FindArgs::default(), &query)?;
    Ok(exit_code(status))
}

fn tee_tail<R, W>(mut reader: R, mut writer: W) -> io::Result<Vec<u8>>
where
    R: Read,
    W: Write,
{
    let mut tail = Tail::new(CAPTURE_BYTES_PER_STREAM);
    let mut buffer = [0_u8; READ_BUFFER_BYTES];
    let mut output_open = true;
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        let chunk = &buffer[..read];
        tail.push(chunk);
        if output_open {
            if let Err(error) = writer.write_all(chunk) {
                if error.kind() == io::ErrorKind::BrokenPipe {
                    output_open = false;
                } else {
                    return Err(error);
                }
            }
        }
    }
    if output_open {
        writer.flush()?;
    }
    Ok(tail.into_bytes())
}

fn join_capture(handle: thread::JoinHandle<io::Result<Vec<u8>>>, stream: &str) -> Result<Vec<u8>> {
    handle
        .join()
        .map_err(|_| anyhow!("{stream} capture thread panicked"))?
        .with_context(|| format!("cannot stream command {stream}"))
}

fn display_command(program: &OsStr, arguments: &[OsString]) -> String {
    std::iter::once(program)
        .chain(arguments.iter().map(OsString::as_os_str))
        .map(|part| part.to_string_lossy())
        .collect::<Vec<_>>()
        .join(" ")
}

fn exit_code(status: std::process::ExitStatus) -> ExitCode {
    if let Some(code) = status.code().and_then(|code| u8::try_from(code).ok()) {
        return ExitCode::from(code);
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(signal) = status.signal() {
            if let Ok(code) = u8::try_from(128_i32.saturating_add(signal)) {
                return ExitCode::from(code);
            }
        }
    }
    ExitCode::FAILURE
}

struct Tail {
    chunks: VecDeque<Vec<u8>>,
    length: usize,
    limit: usize,
}

impl Tail {
    const fn new(limit: usize) -> Self {
        Self {
            chunks: VecDeque::new(),
            length: 0,
            limit,
        }
    }

    fn push(&mut self, bytes: &[u8]) {
        if bytes.len() >= self.limit {
            self.chunks.clear();
            self.chunks
                .push_back(bytes[bytes.len() - self.limit..].to_vec());
            self.length = self.limit;
            return;
        }
        self.chunks.push_back(bytes.to_vec());
        self.length += bytes.len();
        while self.length > self.limit {
            let excess = self.length - self.limit;
            if let Some(front) = self.chunks.front_mut() {
                if front.len() <= excess {
                    self.length -= front.len();
                    self.chunks.pop_front();
                } else {
                    front.drain(..excess);
                    self.length -= excess;
                }
            } else {
                break;
            }
        }
    }

    fn into_bytes(self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(self.length);
        for chunk in self.chunks {
            bytes.extend_from_slice(&chunk);
        }
        bytes
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tail_keeps_bounded_recent_chunks() {
        let mut tail = Tail::new(5);
        tail.push(b"12");
        tail.push(b"345");
        assert_eq!(tail.into_bytes(), b"12345");

        let mut tail = Tail::new(5);
        tail.push(b"12");
        tail.push(b"3456");
        assert_eq!(tail.into_bytes(), b"23456");

        let mut tail = Tail::new(5);
        tail.push(b"1234567");
        assert_eq!(tail.into_bytes(), b"34567");
    }
}
