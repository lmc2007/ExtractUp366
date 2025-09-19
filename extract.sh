#!/data/data/com.termux/files/usr/bin/bash

# 安装必要的依赖
pkg update -y
pkg install python -y
pip install --upgrade pip

# 创建Python脚本
cat > extract_answers.py << 'EOF'
import os
import json
import re
import time
from pathlib import Path

def extract_questions_from_js(file_path):
    """从questionData.js文件中提取问题和答案"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"读取文件时出错 {file_path}: {e}")
        return []
    
    # 尝试查找pageConfig变量
    match = re.search(r'var\s+pageConfig\s*=\s*({.*?});', content, re.DOTALL)
    if not match:
        # 如果没找到，尝试查找任何JavaScript对象
        match = re.search(r'({.*})', content, re.DOTALL)
    
    if not match:
        print(f"无法从 {file_path} 中提取数据")
        return []
    
    json_str = match.group(1)
    
    # 清理JSON字符串
    json_str = re.sub(r'\/\*.*?\*\/', '', json_str)  # 移除 /* */ 注释
    json_str = re.sub(r'\/\/.*?$', '', json_str, flags=re.MULTILINE)  # 移除 // 注释
    json_str = json_str.strip().rstrip(';')  # 移除末尾分号
    
    try:
        # 尝试解析为JSON
        data = json.loads(json_str)
    except json.JSONDecodeError as e:
        print(f"解析JSON时出错 {file_path}: {e}")
        # 尝试修复常见的JSON问题
        try:
            # 尝试修复未加引号的属性名
            json_str = re.sub(r'([{,]\s*)([a-zA-Z0-9_]+)\s*:', r'\1"\2":', json_str)
            data = json.loads(json_str)
        except json.JSONDecodeError as e2:
            print(f"修复后仍无法解析JSON: {e2}")
            return []
    
    questions = []
    
    def extract_question(q_obj):
        """从对象中提取问题数据的辅助函数"""
        try:
            # 清理问题文本中的HTML标签
            question_text = re.sub(r'<[^>]+>', '', q_obj.get('question_text', q_obj.get('questionText', ''))).strip()
            
            # 获取选项
            options = []
            for opt in q_obj.get('options', []):
                opt_id = opt.get('id', opt.get('Id', ''))
                opt_content = opt.get('content', opt.get('Content', ''))
                if opt_id and opt_content:
                    options.append(f"{opt_id}. {opt_content}")
            
            # 获取答案
            answer = q_obj.get('answer_text', q_obj.get('answerText', q_obj.get('answer', '')))
            
            if question_text and options and answer:
                return {
                    'question': question_text,
                    'options': options,
                    'answer': answer,
                    'type': 'choice'  # 标记为选择题
                }
        except Exception as e:
            print(f"提取选择题时出错: {e}")
        return None
    
    def extract_fill_in_answers(q_obj):
        """从对象中提取填空题答案"""
        try:
            # 检查是否有questions_list
            if 'questions_list' in q_obj and q_obj['questions_list']:
                for question in q_obj['questions_list']:
                    # 检查是否有answers_list
                    if 'answers_list' in question and question['answers_list']:
                        answers = []
                        for i, answer in enumerate(question['answers_list'], 1):
                            content = answer.get('content', '')
                            if content:
                                answers.append(f"{i}.{content}")
                        
                        if answers:
                            # 清理问题文本中的HTML标签
                            question_text = re.sub(r'<[^>]+>', '', question.get('question_text', question.get('questionText', ''))).strip()
                            
                            return {
                                'question': question_text if question_text else "填空题",
                                'options': [],
                                'answer': "\n".join(answers),
                                'type': 'fill'  # 标记为填空题
                            }
        except Exception as e:
            print(f"提取填空题答案时出错: {e}")
        return None
    
    def extract_listen_and_answer(q_obj):
        """提取听后回答问题类型的答案"""
        try:
            # 检查是否有record_speak字段
            if 'record_speak' in q_obj and q_obj['record_speak']:
                # 获取最后一个content作为答案
                last_answer = q_obj['record_speak'][-1].get('content', '')
                if last_answer:
                    # 清理问题文本中的HTML标签
                    question_text = re.sub(r'<[^>]+>', '', q_obj.get('question_text', q_obj.get('questionText', ''))).strip()
                    
                    return {
                        'question': question_text if question_text else "听后回答问题",
                        'options': [],
                        'answer': last_answer,
                        'type': 'listen_answer'  # 标记为听后回答问题
                    }
        except Exception as e:
            print(f"提取听后回答问题答案时出错: {e}")
        return None
    
    # 尝试不同的数据结构
    if 'questionObj' in data:
        q_obj = data['questionObj']
        
        # 首先尝试提取选择题
        question = extract_question(q_obj)
        if question:
            questions.append(question)
        else:
            # 如果没有选择题，尝试提取填空题
            fill_question = extract_fill_in_answers(q_obj)
            if fill_question:
                questions.append(fill_question)
            else:
                # 如果没有填空题，尝试提取听后回答问题
                listen_question = extract_listen_and_answer(q_obj)
                if listen_question:
                    questions.append(listen_question)
        
        # 检查多个问题的格式
        if 'questions_list' in q_obj:
            for q in q_obj['questions_list']:
                question = extract_question(q)
                if question:
                    questions.append(question)
    
    # 如果找不到questionObj，尝试直接提取
    else:
        question = extract_question(data)
        if question:
            questions.append(question)
        else:
            # 如果没有选择题，尝试提取填空题
            fill_question = extract_fill_in_answers(data)
            if fill_question:
                questions.append(fill_question)
            else:
                # 如果没有填空题，尝试提取听后回答问题
                listen_question = extract_listen_and_answer(data)
                if listen_question:
                    questions.append(listen_question)
    
    if questions:
        print(f"成功从 {file_path} 中提取到 {len(questions)} 个问题")
    
    return questions

def extract_retell_from_json(file_path):
    """从answer.json文件中提取Retell题的OriginalReference"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        print(f"读取JSON文件时出错 {file_path}: {e}")
        return None
    
    # 检查是否有Data字段和OriginalReference字段
    if 'Data' in data and 'OriginalReference' in data['Data']:
        original_references = data['Data']['OriginalReference']
        if original_references and isinstance(original_references, list):
            # 将多个参考文本合并为一个字符串
            retell_text = "\n\n".join(original_references)
            return {
                'question': "复述题 (Retell)",
                'options': [],
                'answer': retell_text,
                'type': 'retell'  # 标记为复述题
            }
    
    return None

def get_audio_number(audio_file):
    """从音频文件名中提取数字（例如从T8-ZC.mp3中提取8）"""
    match = re.search(r'T(\d+)-ZC\.mp3', audio_file, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return 0  # 如果无法提取数字，返回0

def process_directory(root_dir):
    """处理目录及其子目录中的所有questionData.js和answer.json文件，按音频文件顺序排序"""
    all_questions = []
    processed_files = 0
    
    print(f"正在扫描目录: {root_dir}")
    
    # 收集所有包含questionData.js的目录及其音频文件信息
    dirs_with_js = []
    for root, dirs, files in os.walk(root_dir):
        if 'questionData.js' in files or 'answer.json' in files:
            media_dir = os.path.join(root, 'media')
            audio_files = []
            
            # 检查media文件夹是否存在
            if os.path.exists(media_dir) and os.path.isdir(media_dir):
                # 获取所有音频文件
                for f in os.listdir(media_dir):
                    if f.lower().endswith('.mp3') and 't' in f.lower() and '-zc' in f.lower():
                        audio_files.append(f)
            
            # 按音频文件中的数字排序
            if audio_files:
                audio_files.sort(key=get_audio_number)
                # 只取第一个音频文件（假设每个目录只有一个相关音频）
                audio_number = get_audio_number(audio_files[0])
                
                dirs_with_js.append({
                    'path': root,
                    'audio_number': audio_number
                })
    
    # 按音频文件数字排序目录
    dirs_with_js.sort(key=lambda x: x['audio_number'])
    
    print("\n找到的音频文件顺序:")
    for dir_info in dirs_with_js:
        print(f"T{dir_info['audio_number']}-ZC.mp3 -> {dir_info['path']}")
    
    # 按音频文件顺序处理目录
    for dir_info in dirs_with_js:
        # 处理questionData.js
        js_file_path = os.path.join(dir_info['path'], 'questionData.js')
        if os.path.exists(js_file_path):
            print(f"\n处理文件: {js_file_path}")
            questions = extract_questions_from_js(js_file_path)
            if questions:
                all_questions.extend(questions)
                processed_files += 1
        
        # 处理answer.json
        json_file_path = os.path.join(dir_info['path'], 'answer.json')
        if os.path.exists(json_file_path):
            print(f"处理文件: {json_file_path}")
            retell_question = extract_retell_from_json(json_file_path)
            if retell_question:
                all_questions.append(retell_question)
                processed_files += 1
    
    # 额外扫描所有answer.json文件，确保不会遗漏
    print("\n额外扫描所有answer.json文件...")
    for root, dirs, files in os.walk(root_dir):
        if 'answer.json' in files:
            json_file_path = os.path.join(root, 'answer.json')
            # 检查是否已经处理过这个文件
            if json_file_path not in [os.path.join(dir_info['path'], 'answer.json') for dir_info in dirs_with_js]:
                print(f"处理额外的answer.json文件: {json_file_path}")
                retell_question = extract_retell_from_json(json_file_path)
                if retell_question:
                    all_questions.append(retell_question)
                    processed_files += 1
    
    print(f"\n处理完成！共处理了 {processed_files} 个文件，提取到 {len(all_questions)} 个问题。")
    return all_questions

def save_questions_to_file(questions, output_file):
    """将提取的问题保存到文本文件"""
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("="*80 + "\n")
            f.write("                我真的不会那个...就是那个..... Ciallo～ (∠・ω< )⌒★\n")
            f.write("="*80 + "\n\n")
            
            # 先输出选择题
            choice_questions = [q for q in questions if q.get('type') == 'choice']
            if choice_questions:
                f.write("选择题:\n")
                f.write("="*60 + "\n\n")
                
                for i, q in enumerate(choice_questions, 1):
                    f.write(f"问题 {i}:\n")
                    f.write(f"{q['question']}\n\n")
                    f.write("选项：\n")
                    for opt in q['options']:
                        f.write(f"  {opt}\n")
                    f.write(f"\n答案: {q['answer']}\n")
                    f.write("\n" + "-"*60 + "\n\n")
            
            # 再输出填空题
            fill_questions = [q for q in questions if q.get('type') == 'fill']
            if fill_questions:
                f.write("\n填空题:\n")
                f.write("="*60 + "\n\n")
                
                for i, q in enumerate(fill_questions, 1):
                    f.write(f"问题 {i}:\n")
                    f.write(f"{q['question']}\n\n")
                    f.write(f"答案:\n{q['answer']}\n")
                    f.write("\n" + "-"*60 + "\n\n")
            # 输出复述题
            retell_questions = [q for q in questions if q.get('type') == 'retell']
            if retell_questions:
                f.write("\n复述题 (Retell):\n")
                f.write("="*60 + "\n\n")
                
                for i, q in enumerate(retell_questions, 1):
                    f.write(f"问题 {i}:\n")
                    f.write(f"{q['question']}\n\n")
                    f.write(f"参考文本:\n{q['answer']}\n")
                    f.write("\n" + "-"*60 + "\n\n")
            # 朗读回答问题
            listen_questions = [q for q in questions if q.get('type') == 'listen_answer']
            if listen_questions:
                f.write("\n朗读短文并回答问题:\n")
                f.write("="*60 + "\n\n")
                
                for i, q in enumerate(listen_questions, 1):
                    f.write(f"问题 {i}:\n")
                    f.write(f"{q['question']}\n\n")
                    f.write(f"答案: {q['answer']}\n")
                    f.write("\n" + "-"*60 + "\n\n")
            
            
        
        print(f"\n成功提取 {len(questions)} 个问题，已保存到: {output_file}")
    except Exception as e:
        print(f"保存文件时出错: {e}")

if __name__ == "__main__":
    import sys
    # 包含问题的目录
    current_dir = os.path.dirname(os.path.abspath(__file__))

    if len(sys.argv) > 1:
        subdirectory = sys.argv[1]
    else:
        subdirectory = input("请输入子目录名称（例如 d088f054a07a4718ba415ff39ec7e98f）: ")

    # 构建相对路径
    root_directory = os.path.join(current_dir, subdirectory, "questions")
    output_file = os.path.join(current_dir, "answer.txt")

    print(f"问题目录: {root_directory}")
    print(f"输出文件: {output_file}")
    
    print("="*60)
    print("        开始提取问题和答案")
    print("="*60 + "\n")
    
    # 处理所有问题文件
    questions = process_directory(root_directory)
    
    if questions:
        # 保存到文件
        save_questions_to_file(questions, output_file)
        
        print("\n" + "="*60)
        print(f"处理完成！共提取 {len(questions)} 个问题。")
        print(f"结果已保存到: {output_file}")
        print("="*60)
        time.sleep(15)
    else:
        print("\n未找到任何问题，请检查目录路径是否正确。")
EOF

# 运行Python脚本
echo "请输入子目录名称（例如 d088f054a07a4718ba415ff39ec7e98f）:"
read subdirectory

python extract_answers.py "$subdirectory"

# 清理文件
rm extract_answers.py

echo "脚本执行完成！答案已保存到 answer.txt"