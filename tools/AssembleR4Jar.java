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
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.IntInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;

public final class AssembleR4Jar {
    private static final String CLUSTER_SERVICE =
        "de/audi/tghu/navi/app/cluster/ClusterService.class";

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            throw new IllegalArgumentException(
                "usage: input.jar replacement-classes-dir output.jar");
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

                if (CLUSTER_SERVICE.equals(name)) {
                    bytes = patchNeutralContext(bytes);
                }

                writeEntry(output, name, entry.getTime(), bytes);
                written.add(name);
            }
            addNewClasses(output, classes, classes, written);
        } finally {
            output.close();
            input.close();
        }
    }

    private static byte[] patchNeutralContext(byte[] original) {
        ClassNode node = new ClassNode(Opcodes.ASM9);
        new ClassReader(original).accept(node, 0);
        int patches = 0;
        for (Iterator methods = node.methods.iterator(); methods.hasNext();) {
            MethodNode method = (MethodNode) methods.next();
            if (!"deactivateCustomRendererPipeline".equals(method.name)) continue;
            for (AbstractInsnNode insn = method.instructions.getFirst();
                    insn != null; insn = insn.getNext()) {
                if (!(insn instanceof MethodInsnNode)) continue;
                MethodInsnNode call = (MethodInsnNode) insn;
                if (!"switchContext".equals(call.name)) continue;

                AbstractInsnNode cursor = previousReal(insn);
                cursor = previousReal(cursor);
                cursor = previousReal(cursor);
                if (cursor instanceof IntInsnNode
                        && cursor.getOpcode() == Opcodes.BIPUSH
                        && ((IntInsnNode) cursor).operand == 74) {
                    ((IntInsnNode) cursor).operand = 72;
                    patches++;
                }
            }
        }
        if (patches != 1) {
            throw new IllegalStateException(
                "expected exactly one ClusterService teardown context patch, got " + patches);
        }
        ClassWriter writer = new ClassWriter(0);
        node.accept(writer);
        return writer.toByteArray();
    }

    private static AbstractInsnNode previousReal(AbstractInsnNode node) {
        if (node == null) return null;
        AbstractInsnNode cursor = node.getPrevious();
        while (cursor != null && cursor.getOpcode() < 0) cursor = cursor.getPrevious();
        return cursor;
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
