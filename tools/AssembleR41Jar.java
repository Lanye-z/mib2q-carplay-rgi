import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.jar.JarOutputStream;

import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.FieldNode;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.MethodNode;

public final class AssembleR41Jar {
    private static final String CARPLAY_HOOK =
        "com/luka/carplay/CarPlayHook.class";
    private static final String OLD_BUILD_ID =
        "2026-08-03-neutral-context-uturn-r4";
    private static final String NEW_BUILD_ID =
        "2026-08-04-lazy-renderer-gate-release-r4.1";

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            throw new IllegalArgumentException(
                "usage: input-r4.jar replacement-classes-dir output.jar");
        }

        File classes = new File(args[1]);
        JarFile input = new JarFile(args[0]);
        JarOutputStream output = new JarOutputStream(new FileOutputStream(args[2]));
        Set written = new HashSet();
        try {
            Enumeration entries = input.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = (JarEntry) entries.nextElement();
                String name = entry.getName();
                File replacement = new File(classes, name.replace('/', File.separatorChar));
                byte[] bytes = replacement.isFile()
                    ? readAll(new FileInputStream(replacement))
                    : readAll(input.getInputStream(entry));

                if (CARPLAY_HOOK.equals(name)) bytes = patchBuildId(bytes);
                writeEntry(output, name, entry.getTime(), bytes);
                written.add(name);
            }
            addNewClasses(output, classes, classes, written);
        } finally {
            output.close();
            input.close();
        }
    }

    private static byte[] patchBuildId(byte[] original) {
        ClassNode node = new ClassNode(org.objectweb.asm.Opcodes.ASM9);
        new ClassReader(original).accept(node, 0);
        int patches = 0;
        for (Iterator fields = node.fields.iterator(); fields.hasNext();) {
            FieldNode field = (FieldNode) fields.next();
            if (field.value instanceof String) {
                String value = (String) field.value;
                if (value.indexOf(OLD_BUILD_ID) >= 0) {
                    field.value = replaceBuildId(value);
                    patches++;
                }
            }
        }
        for (Iterator methods = node.methods.iterator(); methods.hasNext();) {
            MethodNode method = (MethodNode) methods.next();
            for (AbstractInsnNode insn = method.instructions.getFirst();
                    insn != null; insn = insn.getNext()) {
                if (insn instanceof LdcInsnNode
                        && ((LdcInsnNode) insn).cst instanceof String) {
                    LdcInsnNode ldc = (LdcInsnNode) insn;
                    String value = (String) ldc.cst;
                    if (value.indexOf(OLD_BUILD_ID) >= 0) {
                        ldc.cst = replaceBuildId(value);
                        patches++;
                    }
                }
            }
        }
        if (patches == 0) {
            throw new IllegalStateException("R4 build ID not found in CarPlayHook");
        }
        ClassWriter writer = new ClassWriter(0);
        node.accept(writer);
        return writer.toByteArray();
    }

    private static String replaceBuildId(String value) {
        int index = value.indexOf(OLD_BUILD_ID);
        return value.substring(0, index) + NEW_BUILD_ID
            + value.substring(index + OLD_BUILD_ID.length());
    }

    private static void addNewClasses(JarOutputStream output, File root,
            File directory, Set written) throws Exception {
        File[] files = directory.listFiles();
        if (files == null) return;
        for (int i = 0; i < files.length; i++) {
            File file = files[i];
            if (file.isDirectory()) {
                addNewClasses(output, root, file, written);
                continue;
            }
            String name = file.getPath().substring(root.getPath().length() + 1)
                .replace(File.separatorChar, '/');
            if (!name.endsWith(".class") || written.contains(name)) continue;
            writeEntry(output, name, file.lastModified(),
                readAll(new FileInputStream(file)));
            written.add(name);
        }
    }

    private static void writeEntry(JarOutputStream output, String name,
            long time, byte[] bytes) throws Exception {
        JarEntry entry = new JarEntry(name);
        entry.setTime(time);
        output.putNextEntry(entry);
        output.write(bytes);
        output.closeEntry();
    }

    private static byte[] readAll(InputStream input) throws Exception {
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) >= 0) output.write(buffer, 0, count);
            return output.toByteArray();
        } finally {
            input.close();
        }
    }
}
